#!/usr/bin/env bash

# Creates the examples database and respective user.
# Database location and access credentials are defined via environment variables.

set -e

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" <<-EOSQL
  CREATE USER ${EXAMPLES_USER} WITH PASSWORD '${EXAMPLES_PASSWORD}';
  CREATE DATABASE ${EXAMPLES_DB};
  GRANT ALL PRIVILEGES ON DATABASE ${EXAMPLES_DB} TO ${EXAMPLES_USER};
EOSQL

psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" -d "${EXAMPLES_DB}" <<-EOSQL
   GRANT ALL ON SCHEMA public TO ${EXAMPLES_USER};
EOSQL
