SELECT COUNT(*) > 0 AS test
FROM information_schema.triggers
WHERE trigger_schema = 'sqm_examples'
AND trigger_name = 'tg_user_modified_time';
