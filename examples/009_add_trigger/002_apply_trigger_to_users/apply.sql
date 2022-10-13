CREATE TRIGGER tg_user_modified_time
AFTER UPDATE ON sqm_examples.users
FOR EACH ROW 
WHEN (pg_trigger_depth() = 0) -- prevent recursion
EXECUTE PROCEDURE sqm_examples.update_modified_time();
