SELECT COUNT(*) as test
FROM information_schema.columns
WHERE table_schema='sqm_examples'
AND table_name='users'
AND column_name='name'
AND is_nullable::bool=false;
