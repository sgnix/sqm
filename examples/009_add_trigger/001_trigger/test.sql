SELECT COUNT(*) > 0 AS test
FROM information_schema.routines
WHERE specific_schema = 'sqm_examples'
AND routine_name = 'update_modified_time';
