--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P00 - Baseline and Environment
-- Execution target: Oracle APEX SQL Workshop -> SQL Scripts
-- Purpose: Read-only verification of a hosted Oracle/APEX workspace.
-- Safety: This script performs no DDL or DML and creates no objects.
-- Note: It deliberately avoids SQLcl/SQL*Plus PROMPT commands.
--------------------------------------------------------------------------------

select '01_IDENTITY'                             as check_section,
       user                                      as parsing_schema,
       sys_context('USERENV', 'DB_NAME')         as database_name,
       sys_context('USERENV', 'CURRENT_SCHEMA')  as current_schema,
       sys_context('USERENV', 'SESSION_USER')    as session_user,
       sys_context('USERENV', 'LANGUAGE')        as session_language,
       sessiontimezone                           as session_timezone,
       current_timestamp                         as checked_at
  from dual;

select '02_DATABASE_VERSION'                     as check_section,
       dbms_db_version.version                   as database_major_version,
       dbms_db_version.release                   as database_release
  from dual;

select '03_APEX_VERSION'                         as check_section,
       version_no                                as apex_version
  from apex_release;

select '04_OBJECT_BASELINE'                      as check_section,
       object_type,
       count(*)                                  as object_count
  from user_objects
 group by object_type
 order by object_type;

select '05_INVALID_OBJECTS'                      as check_section,
       object_name,
       object_type,
       status
  from user_objects
 where status = 'INVALID'
 order by object_type, object_name;

select '06_EXISTING_OF_OBJECTS'                  as check_section,
       object_name,
       object_type,
       status
  from user_objects
 where object_name like 'OF\_%' escape '\'
 order by object_type, object_name;

select '07_NLS_SETTINGS'                         as check_section,
       parameter,
       value
  from nls_session_parameters
 where parameter in (
         'NLS_DATE_FORMAT',
         'NLS_TIMESTAMP_FORMAT',
         'NLS_TIMESTAMP_TZ_FORMAT',
         'NLS_DATE_LANGUAGE',
         'NLS_NUMERIC_CHARACTERS',
         'NLS_SORT',
         'NLS_COMP'
       )
 order by parameter;
