SELECT COUNT(*) > 0 AS test 
FROM pg_stat_all_indexes 
WHERE schemaname = 'sqm_examples'
AND indexrelname = 'ix_users_email';
