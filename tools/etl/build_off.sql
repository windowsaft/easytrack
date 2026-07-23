-- Production Open Food Facts extraction — the release pipeline.
--
--   duckdb -c ".read tools/etl/build_off.sql"
--
-- Runs on the build machine / CI, never on the phone. Filters the Open Food
-- Facts dump down to a region and emits a JSON array of products, which
-- build_off.mjs then normalizes (German search text + compound morphemes) and
-- writes into off_<region>.sqlite with its FTS index and pack_meta. Keeping the
-- normalizer in one place (Node) is what guarantees the index and the runtime
-- query fold text identically; doing it in SQL here would be a second, drifting
-- implementation.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- BLOCKING: verify the schema before trusting this query.
--
-- The HuggingFace `food.parquet` does NOT expose flat nutrient columns, and
-- `product_name` is a nested LIST(STRUCT(lang, text)) rather than a string. The
-- exact shape has changed across dumps, so run this FIRST and reconcile the
-- column and struct-field names below with the output:
--
--   duckdb -c "DESCRIBE SELECT * FROM read_parquet('food.parquet');"
--
-- Documented fallback if the parquet layout fights back: stream the JSONL.gz
-- export instead (read_json_auto), same WHERE clause.
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Parquet is columnar, so the projection + predicate below are pushed down: a
-- few hundred MB are read instead of decompressing the ~9 GB TSV. Set REGION by
-- editing the countries filter; the plan ships three variants (de / dach /
-- world) built by running this three times.

INSTALL json;
LOAD json;

-- Adjust the path and region to taste. `food.parquet` is the HuggingFace dump:
--   https://huggingface.co/datasets/openfoodfacts/product-database
COPY (
  WITH raw AS (
    SELECT
      code AS barcode,
      -- product_name is LIST(STRUCT(lang, text)); prefer the German entry, then
      -- the "main" one, then whatever exists. list_filter + [1] pulls one text.
      COALESCE(
        list_filter(product_name, x -> x.lang = 'de')[1].text,
        list_filter(product_name, x -> x.lang = 'main')[1].text,
        product_name[1].text
      ) AS name,
      brands,
      -- Nutriments are a LIST(STRUCT(name, value_100g, ...)) in recent dumps.
      -- Pull the per-100g value for each core nutrient. VERIFY these field names.
      list_filter(nutriments, n -> n.name = 'energy-kcal')[1]."100g" AS kcal,
      list_filter(nutriments, n -> n.name = 'proteins')[1]."100g"    AS protein_g,
      list_filter(nutriments, n -> n.name = 'carbohydrates')[1]."100g" AS carbs_g,
      list_filter(nutriments, n -> n.name = 'fat')[1]."100g"         AS fat_g,
      list_filter(nutriments, n -> n.name = 'sugars')[1]."100g"      AS sugar_g,
      list_filter(nutriments, n -> n.name = 'saturated-fat')[1]."100g" AS sat_fat_g,
      list_filter(nutriments, n -> n.name = 'salt')[1]."100g"        AS salt_g,
      list_filter(nutriments, n -> n.name = 'fiber')[1]."100g"       AS fiber_g,
      serving_quantity AS serving_size_g,
      completeness AS completeness_score,
      -- OFF category slugs, e.g. ['en:beverages','en:sodas']. The app reads them
      -- for robust drink detection (ml vs g), so a Cola is a beverage by tag,
      -- not by a fragile name-keyword guess.
      categories_tags,
      countries_tags
    FROM read_parquet('food.parquet')
  )
  SELECT
    barcode, name, brands, serving_size_g,
    kcal, protein_g, carbs_g, fat_g,
    sugar_g, sat_fat_g, salt_g, fiber_g,
    completeness_score, categories_tags
  FROM raw
  WHERE
    barcode IS NOT NULL
    AND length(trim(name)) >= 2
    -- DACH. For `de` keep only germany; for `world` drop this clause.
    AND (
      list_contains(countries_tags, 'en:germany')
      OR list_contains(countries_tags, 'en:austria')
      OR list_contains(countries_tags, 'en:switzerland')
    )
    -- The four core macros must be present (mirrors isValidProduct in the mjs).
    AND kcal IS NOT NULL
    AND protein_g IS NOT NULL
    AND carbs_g IS NOT NULL
    AND fat_g IS NOT NULL
    -- Physically possible: nothing edible beats pure fat (~900 kcal/100 g).
    AND kcal BETWEEN 0 AND 950
    -- Macro sum has to fit inside 100 g, with slack for rounding.
    AND (protein_g + carbs_g + fat_g) <= 105
  -- Deterministic de-dupe: one row per barcode, most complete wins.
  QUALIFY row_number() OVER (
    PARTITION BY barcode ORDER BY completeness_score DESC NULLS LAST
  ) = 1
) TO 'tools/etl/dist/off_dach_products.json' (FORMAT JSON, ARRAY true);

-- Then, on the build machine:
--   node tools/etl/build_off.mjs --region dach \
--     --seed tools/etl/dist/off_dach_products.json \
--     --base-url https://github.com/<owner>/<repo>/releases/download/off-latest
