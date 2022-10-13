SELECT COUNT(*) > 0 AS test
FROM information_schema.columns
WHERE table_schema = 'sqm_examples'
AND table_name = 'users'
AND column_name = 'access';
