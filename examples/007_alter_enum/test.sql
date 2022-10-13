SELECT 
  CASE 
    WHEN COUNT(*) > 0 THEN 1 
    ELSE 0 
  END AS test 
FROM (
  SELECT
    pn.nspname AS enum_schema,
    pt.typname AS enum_name,
    pe.enumlabel AS enum_value
  FROM pg_type pt
  JOIN pg_enum pe ON pt.oid = pe.enumtypid
  JOIN pg_catalog.pg_namespace pn ON pn.oid = pt.typnamespace
) enums_view
WHERE enum_schema = 'sqm_examples'
AND enum_name = 'user_access'
AND enum_value = 'superuser';
