cd /cartodb

bundle exec  rake cartodb:db:create_user --trace SUBDOMAIN="geocoder" \
	PASSWORD=$CARTO_GEOCODER_PW ADMIN_PASSWORD=$CARTO_GEOCODER_ADMIN_PW \
	EMAIL=$CARTO_GEOCODER_EMAIL

# # Update your quota to 100GB
echo "--- Updating quota to 100GB"
bundle exec  rake cartodb:db:set_user_quota[geocoder,102400]

# # Allow unlimited tables to be created
echo "--- Allowing unlimited tables creation"
bundle exec  rake cartodb:db:set_unlimited_table_quota[geocoder]

GEOCODER_DB=`echo "SELECT database_name FROM users WHERE username='geocoder'" | psql -U postgres -t carto_db_production`
psql -U postgres $GEOCODER_DB < /cartodb/script/geocoder_server.sql

# Import observatory test dataset
psql -U postgres -d $GEOCODER_DB -f /observatory-extension/src/pg/test/fixtures/load_fixtures.sql
# Setup permissions for observatory
psql -U postgres -d $GEOCODER_DB -c "BEGIN;CREATE EXTENSION IF NOT EXISTS observatory VERSION 'prod'; COMMIT" -e
psql -U postgres -d $GEOCODER_DB -c "BEGIN;GRANT SELECT ON ALL TABLES IN SCHEMA cdb_observatory TO geocoder; COMMIT" -e
psql -U postgres -d $GEOCODER_DB -c "BEGIN;GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA cdb_observatory TO geocoder; COMMIT" -e
psql -U postgres -d $GEOCODER_DB -c "BEGIN;GRANT SELECT ON ALL TABLES IN SCHEMA observatory TO geocoder; COMMIT" -e
psql -U postgres -d $GEOCODER_DB -c "BEGIN;GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA observatory TO geocoder; COMMIT" -e

# Setup dataservices client
# dev user
USER_DB=`echo "SELECT database_name FROM users WHERE username='$CARTO_USER_SUBDOMAIN'" | psql -U postgres -t carto_db_production`
echo "CREATE EXTENSION cdb_dataservices_client;" | psql -U postgres $USER_DB
echo "SELECT CDB_Conf_SetConf('user_config', '{"'"is_organization"'": false, "'"entity_name"'": "'"$CARTO_USER_SUBDOMAIN"'"}');" | psql -U postgres $USER_DB
echo -e "SELECT CDB_Conf_SetConf('geocoder_server_config', '{ \"connection_str\": \"host=localhost port=5432 dbname=${GEOCODER_DB# } user=postgres\"}');" | psql -U postgres $USER_DB
bundle exec  rake cartodb:services:set_user_quota[$CARTO_USER_SUBDOMAIN,geocoding,100000]

# example organization
ORGANIZATION_DB=`echo "SELECT database_name FROM users WHERE username='$CARTO_ORG_USERNAME'" | psql -A -U postgres -t carto_db_production`
echo "CREATE EXTENSION cdb_dataservices_client;" | psql -U postgres $ORGANIZATION_DB
echo "SELECT CDB_Conf_SetConf('user_config', '{"'"is_organization"'": true, "'"entity_name"'": "'"$CARTO_ORG_NAME"'"}');" | psql -U postgres $ORGANIZATION_DB
echo -e "SELECT CDB_Conf_SetConf('geocoder_server_config', '{ \"connection_str\": \"host=localhost port=5432 dbname=${GEOCODER_DB# } user=postgres\"}');" | psql -U postgres $ORGANIZATION_DB
bundle exec  rake cartodb:services:set_org_quota[$CARTO_ORG_NAME,geocoding,100000]
