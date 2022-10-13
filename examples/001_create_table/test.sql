SELECT COUNT(*) > 0 AS test
FROM information_schema.tables
WHERE table_schema = 'sqm_examples'
AND table_name = 'users';
