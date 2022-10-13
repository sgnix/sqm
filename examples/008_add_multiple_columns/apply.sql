BEGIN;

ALTER TABLE sqm_examples.users
  ADD created_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD modified_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX ix_users_created_time ON sqm_examples.users(created_time);

COMMIT;
