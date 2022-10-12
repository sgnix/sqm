#!/usr/bin/env bash
#
# Usage: 
#   $0 run <path> [-d <database>] [-n] [-q]
#   $0 stat <path> -d <database> [-i]
#   $0 list <path>
#   $0 sanity
#   $0 help | docs
#
# Commands:
#   run              run migrations
#   stat             view applied migrations for db (-i for unapplied)
#   list             list the migrations for a path
#   sanity           run sanity check
#   help             this help message
#   docs             print manual and documentation
#
# Options:
#   -i               invert results (show unapplied migrations)
#   -d <database>    run on database/schema name only
#   -n               dry run, do not apply migrations
#   -q               quiet, no output
#
# Environment Variables
#   MYSQL_CLIENT       full path of mysql
#   MYSQL_ARGS         mysql arguments
#

set -uo pipefail

OK_MSG="\033[1;32m[OK]\033[0;0m"
ERROR_MSG="\033[1;31m[ERROR]\033[0;0m"
WARN_MSG="\033[1;33m[WARN]\033[0;0m"

MYSQL_CLIENT=${MYSQL_CLIENT:-$(which mysql)}
MYSQL_ARGS=${MYSQL_ARGS:=}

SCHEMATA_NAME=schemata.sql
SCHEMATA_COLUMN=schemata

APPLY_NAME=apply.sql
TEST_NAME=test.sql
TEST_COLUMN="test"

usage() {
  tail +2 "$0" | while read -r line
    do 
      if ! [[ $line =~ ^# ]]; then break; fi 
    eval "echo \"$line\"" | sed 's/^#//' | sed 's/^ //'
    done 

  exit 0
}

docs() {
  local found=0
  cat "$0" | while read -r line
  do
    if [[ $found -eq 0 ]]; then
      if [[ "$line" != "# DOCS BEGIN" ]]; then
        continue
      else
        found=1
        continue
      fi
    fi

    eval "echo \"$line\"" | sed 's/^#//' | sed 's/^ //'
  done

  exit 0
}

error() {
  >&2 echo -e "$ERROR_MSG $1"
  exit 255
}

verb() {
  if [[ -z ${QUIET:-} ]]; then
    echo -e "$1"
  fi
}

check_path() {
  if [[ -z ${MIGRATIONS:-} ]]; then
    error "Please specify path to migrations"
  fi

  if [[ ! -d $MIGRATIONS ]]; then
    error "Invalid path: $MIGRATIONS"
  fi
}

# Gets a list of tables based on a file name
find_schemata_file() {
  local rel_dir
  local dir

  rel_dir=$(dirname "$1")
  dir=$(cd "$rel_dir" || exit; pwd)

  while [[ "$dir" != "/" ]]
  do
    if [[ -f "$dir/$SCHEMATA_NAME" ]]; then
      echo "$dir/$SCHEMATA_NAME"
      break
    fi

    dir=$(dirname "$dir")
  done
}

sanity_check() {
  local quiet=${1:-}

  if [[ -n $MYSQL_CLIENT ]] && [[ -x $MYSQL_CLIENT ]]; then
    [[ -z $quiet ]] && verb "$OK_MSG MySQL client found"
  else
    error "MySQL client not found"
  fi

  if [[ -n $(echo "select SCHEMA_NAME from information_schema.SCHEMATA" | $MYSQL_CLIENT $MYSQL_ARGS ) ]];
  then
    [[ -z ${quiet:-} ]] && verb "$OK_MSG MySQL connection successful"
  else
    error "Can't connect my MySQL"
  fi
}

# Test the outcome of a result
test_sql() {
  local db=$1
  local fn=$2
  local res
  local col
  local val

  res=$($MYSQL_CLIENT $MYSQL_ARGS "$db" < "$fn")
  [[ -z $res ]] && error "No result: $fn"

  col=$(echo "$res" | head -n1)
  val=$(echo "$res" | tail -1)

  if [[ $col != "$TEST_COLUMN" ]]; then
    error "No '$TEST_COLUMN' column: $fn"
  fi

  if [[ -z $val ]] || [[ $val -ne 0 ]] && [[ $val -ne 1 ]]; then
    error "Test did not return 1/0 value: $fn"
  fi

  echo "$val"
}

# Get the schemata from a file
get_schemata() {
  local fn=$1
  local res
  local col
  local schemata

  # Load the names of the tables from the schemata file
  res=$($MYSQL_CLIENT $MYSQL_ARGS < "$fn")
  [[ -z $res ]] && error "No schemata: $fn"

  col=$(echo "$res" | head -1)
  schemata=$(echo "$res" | tail +2)
  
  # Check if the column name is correct
  if [[ $col != "$SCHEMATA_COLUMN" ]]; then
    error "No '$SCHEMATA_COLUMN' column: $fn "
  fi

  if [[ -z $schemata ]]; then
    error "No schemata: $fn" 
  fi

  echo "$schemata"
}

run() {
  local test_files

  # Find all test files under the migrations path and sort them
  test_files=$(find "$MIGRATIONS" -name $TEST_NAME | sort)

  # Iterate over the sorted list of test files (full path)
  for fn in $test_files
  do
    local dir
    local schemata_file
    local schemata

    dir=$(dirname "$fn")
    verb "Applying: $dir"

    # Find the schemata file for the currently processed directory
    schemata_file=$(find_schemata_file "$fn")
    if [[ -z ${schemata_file:-} ]]; then
      error "No $SCHEMATA_NAME file found for path $dir"
    fi

    schemata=$(get_schemata "$schemata_file") || { echo "$schemata"; exit 255; }

    # If DB_NAME was specified with the -d switch, then run on that db only
    if [[ -n ${DB_NAME:-} ]] && [[ $(echo "$schemata" | grep -w "$DB_NAME") ]]; then
      schemata=$DB_NAME
    fi

    # Iterate over the schemata
    for db in $schemata
    do
      local exists
      local val

      # Check if the schema exists
      exists=$(echo "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '$db'" | $MYSQL_CLIENT $MYSQL_ARGS)
      if [[ -z ${exists:-} ]]; then
        verb "$WARN_MSG not found: $db"
        continue
      fi

      # Test if the schema needs migration
      val=$(test_sql "$db" "$fn") || { echo "$val"; exit 255; }

      if [[ $val -eq 0 ]]; then
        if [[ -n ${DRY:-} ]]; then
          verb "$OK_MSG (dry run) $db"
        else
          if ! $MYSQL_CLIENT $MYSQL_ARGS "$db" < "$dir"/$APPLY_NAME; then
            error "Failed $db: $dir/$APPLY_NAME"
          else
            # Verify
            val=$(test_sql "$db" "$fn") || { echo "$val"; exit 255; }
            if [[ $val -eq 1 ]]; then
              verb "$OK_MSG $db"
            else
              error "$db failed test: $fn"
            fi
          fi
        fi
      fi
    done
  done
}

stat() {
  [[ -z ${DB_NAME:-} ]] && error "Please specify database name"

  local test_files
  
  # Find all test files under the migrations path and sort them
  test_files=$(find "$MIGRATIONS" -name $TEST_NAME | sort)

  for fn in $test_files
  do
    local dir
    local schemata_file
    local schemata
    local found

    dir=$(dirname "$fn")

    # Find the schemata file for the currently processed directory
    schemata_file=$(find_schemata_file "$fn")
    if [[ -z ${schemata_file:-} ]]; then
      error "No $SCHEMATA_NAME file found for path $dir"
    fi

    schemata=$(get_schemata "$schemata_file") || { echo "$schemata"; exit 255; }

    found=$(echo "$schemata" | grep -w "$DB_NAME")
    if [[ $found ]]; then
      local val
      val=$(test_sql "$DB_NAME" "$fn") || { echo "$val"; exit 255; }
      if [[ -z ${STAT_INVERT:-} ]]; then
        [[ $val -eq 1 ]] && echo "$dir" 
      else
        [[ $val -eq 0 ]] && echo "$dir"
      fi
    fi
  done
}

process_opts() {
  local OPTIND
  while getopts "d:inq" opt
  do
    case $opt in
      d) DB_NAME="$OPTARG" ;;
      i) STAT_INVERT=1 ;;
      n) DRY=1 ;;
      q) QUIET=1 ;;
      *) usage ;;
    esac
  done
}

if [[ $# -eq 0 ]]; then
  usage
else
  case $1 in
    run)
      MIGRATIONS=${2:-}
      shift; shift
      process_opts "$@"
      check_path
      sanity_check 1
      run
      ;;

    stat)
      MIGRATIONS=${2:-}
      shift; shift
      process_opts "$@"
      check_path
      sanity_check 1
      stat
      ;;

    list)
      MIGRATIONS=${2:-}
      check_path
      find "$MIGRATIONS" -name $TEST_NAME | sort | sed 's/test.sql$//'
      ;;

    sanity)
      sanity_check
      exit 0
      ;;

    help) 
      usage 
      ;;

    docs)
      docs
      ;;

    *) 
      error "Invalid command: $1\nRun '$0 help' for help."
      ;;
  esac
fi

exit 0

# DOCS BEGIN
# $0
# 
# NAME
#     $0 -- SQL Migration Tool
#
# SYNOPSIS
#     $0 <command> <path> [options]

# DESCRIPTION
#     The $0 utility is a version and schema agnostic tool for database
#     migrations. Currently it only works with MySQL and there are no
#     short term plans to port it to any other database.
#
# DETAILS
#     This tool works by traversing the specified migrations tree and applying
#     all eligible migrations to a predefined set of schemata. The migrations
#     tree can be any path in the current file system and it's specified with
#     the path parameter.  An eligible migration is a directory which contains
#     these two files: $APPLY_NAME and $TEST_NAME. The $TEST_NAME file is
#     responsible to determine if the migration should run on the currently
#     processed schema or not. The $APPLY_NAME contains the actual migration. A
#     third file $SCHEMATA_NAME must be present in the migration tree. It
#     should return the names of the schemata on which to run the migrations.
#     Each migration will look for the $SCHEMATA_NAME file that is closest to
#     it in the migration tree. So, if this file is found in the current
#     migration directory then it will be used, otherwise it will be searched
#     for up the tree until its found or an error will be produced.
#     
# FILES
#     There are three special files that play into the schema migration:
#
#      * $SCHEMATA_NAME must be present somewhere in the migration tree.  It
#      should contain an SQL statement returning a single column called
#      'schemata' with the names of all schemata to be migrated.  All
#      migrations will search for the closest $SCHEMATA_NAME file, traversing
#      the directory tree upwards until they find it or return an error.  This
#      allows for individual migrations of a narrow the list of applicable
#      schemata or use the 'catch-all' set found upwards the directory tree.
#      Example migration tree with two $SCHEMATA_NAME files:
#
#    migrations/
#      ├── 01_add_data
#      │   ├── $SCHEMATA_NAME
#      │   ├── $TEST_NAME
#      │   └── $APPLY_NAME
#      ├── 02_new_column
#      │   ├── $TEST_NAME
#      │   └── $APPLY_NAME
#      ├── 03_remove_column
#      │   ├── $TEST_NAME
#      │   └── $APPLY_NAME
#      └── $SCHEMATA_NAME
#
#     The top level $SCHEMATA_NAME may contain a wide set of schemata to be
#     migrated, for example:
#
#     SELECT id AS schemata FROM mac.mac_new_apps 
#     WHERE app_type='ss_master'; 
#
#     The $SCHEMATA_NAME file under the 01_add_data directory may narrow (or
#     expand) this set so its migration span is limited (or expanded), versus
#     the other ones which will use the $SCHEMATA_NAME file from the parent
#     directory.
#
#     * $TEST_NAME must be present inside each migration directory. It is a
#     plain SQL file which *must* return a single column named 'test' with a
#     value of 0 if a migration is required and a value of 1 if no migration is
#     necessary. An example SQL for testing if a username 'jack' is present
#     would be:
#
#     SELECT IF(COUNT(*) > 0, 1, 0) AS test 
#     FROM users 
#     WHERE username = 'jack';
#
#     The return value of 0 or 1 can be thought of as answering the following
#     question 'Has the migration defined in $APPLY_NAME been successfully
#     applied, yes or no?'
#
#     * $APPLY_NAME must also be present inside each migration directory. It's a
#     plain SQL file which contains the actual migration. In the example
#     above, this would be:
#     
#     INSERT INTO users (username) VALUES ('jack');
#
# CREATING MIGRATIONS
#     Migrations are simple directories and can be created manually.
#     All migrations will run in alphabetical order, so make sure to
#     name them accordingly.  
#
# RUNNING MIGRATIONS
#     Migrations are run with the 'run' command and a mandatory parameter
#     with migration path. You may run the topmost migration level or any
#     sub-levels as necessary. 
#
# ENV VARIABLES
#     This tool uses the following optional env variables:
#
#     * MYSQL_CLIENT - full path of the MySQL client. By default this script
#     will attempt to locate MySQL, however if that's not possible it will
#     return an error.
#
#     * MYSQL_ARGS - command line arguments to pass to the MySQL client. This
#     will vary from one environment to the next.
#
#     Upon start up, this tool will attempt to validate the MySQL connection,
#     so you will have to make sure that you have sane values for the above
#     variables.
#
