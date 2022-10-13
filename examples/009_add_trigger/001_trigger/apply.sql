CREATE FUNCTION sqm_examples.update_modified_time() RETURNS TRIGGER AS $$
BEGIN
  UPDATE sqm_examples.users SET modified_time=NOW() WHERE id = OLD.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
