--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P02 - Core Relational Schema Validation
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Read-only. This script does not change schema objects or data.
-- Expected: 17 tables, 17 identity columns, no missing indexes, no invalid
--           constraints, no invalid OF_ objects, and zero rows after tests.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. Installation summary
--------------------------------------------------------------------------------

select 'P02_EXPECTED_TABLES_INSTALLED' as check_name,
       count(*) as actual_value,
       17 as expected_value,
       case when count(*) = 17 then 'PASS' else 'FAIL' end as result
  from user_tables
 where table_name in (
   'OF_DEPARTMENTS', 'OF_LOCATIONS', 'OF_APP_USERS', 'OF_ROLES',
   'OF_USER_ROLES', 'OF_APP_SETTINGS', 'OF_AUDIT_LOG', 'OF_ERROR_LOG',
   'OF_NOTIFICATIONS', 'OF_PRIORITIES', 'OF_SERVICE_CATEGORIES',
   'OF_SLA_POLICIES', 'OF_TICKETS', 'OF_TICKET_COMMENTS',
   'OF_TICKET_STATUS_HISTORY', 'OF_TICKET_SLA_PAUSES', 'OF_SLA_EVENTS'
 );

select 'P02_IDENTITY_COLUMNS' as check_name,
       count(*) as actual_value,
       17 as expected_value,
       case when count(*) = 17 then 'PASS' else 'FAIL' end as result
  from user_tab_identity_cols
 where table_name in (
   'OF_DEPARTMENTS', 'OF_LOCATIONS', 'OF_APP_USERS', 'OF_ROLES',
   'OF_USER_ROLES', 'OF_APP_SETTINGS', 'OF_AUDIT_LOG', 'OF_ERROR_LOG',
   'OF_NOTIFICATIONS', 'OF_PRIORITIES', 'OF_SERVICE_CATEGORIES',
   'OF_SLA_POLICIES', 'OF_TICKETS', 'OF_TICKET_COMMENTS',
   'OF_TICKET_STATUS_HISTORY', 'OF_TICKET_SLA_PAUSES', 'OF_SLA_EVENTS'
 )
   and column_name = 'ID';

--------------------------------------------------------------------------------
-- 02. Missing or unexpected tables
-- Expected result for both queries: no rows selected.
--------------------------------------------------------------------------------

with expected_tables (table_name) as (
  select 'OF_DEPARTMENTS' from dual union all
  select 'OF_LOCATIONS' from dual union all
  select 'OF_APP_USERS' from dual union all
  select 'OF_ROLES' from dual union all
  select 'OF_USER_ROLES' from dual union all
  select 'OF_APP_SETTINGS' from dual union all
  select 'OF_AUDIT_LOG' from dual union all
  select 'OF_ERROR_LOG' from dual union all
  select 'OF_NOTIFICATIONS' from dual union all
  select 'OF_PRIORITIES' from dual union all
  select 'OF_SERVICE_CATEGORIES' from dual union all
  select 'OF_SLA_POLICIES' from dual union all
  select 'OF_TICKETS' from dual union all
  select 'OF_TICKET_COMMENTS' from dual union all
  select 'OF_TICKET_STATUS_HISTORY' from dual union all
  select 'OF_TICKET_SLA_PAUSES' from dual union all
  select 'OF_SLA_EVENTS' from dual
)
select table_name as missing_table
  from expected_tables
minus
select table_name
  from user_tables;

with expected_tables (table_name) as (
  select 'OF_DEPARTMENTS' from dual union all
  select 'OF_LOCATIONS' from dual union all
  select 'OF_APP_USERS' from dual union all
  select 'OF_ROLES' from dual union all
  select 'OF_USER_ROLES' from dual union all
  select 'OF_APP_SETTINGS' from dual union all
  select 'OF_AUDIT_LOG' from dual union all
  select 'OF_ERROR_LOG' from dual union all
  select 'OF_NOTIFICATIONS' from dual union all
  select 'OF_PRIORITIES' from dual union all
  select 'OF_SERVICE_CATEGORIES' from dual union all
  select 'OF_SLA_POLICIES' from dual union all
  select 'OF_TICKETS' from dual union all
  select 'OF_TICKET_COMMENTS' from dual union all
  select 'OF_TICKET_STATUS_HISTORY' from dual union all
  select 'OF_TICKET_SLA_PAUSES' from dual union all
  select 'OF_SLA_EVENTS' from dual
)
select table_name as unexpected_of_table
  from user_tables
 where table_name like 'OF\_%' escape '\'
minus
select table_name
  from expected_tables;

--------------------------------------------------------------------------------
-- 03. Constraint and object health
-- Expected result for both queries: no rows selected.
--------------------------------------------------------------------------------

select table_name,
       constraint_name,
       constraint_type,
       status,
       validated
  from user_constraints
 where table_name like 'OF\_%' escape '\'
   and (status <> 'ENABLED' or validated <> 'VALIDATED')
 order by table_name, constraint_name;

select object_name,
       object_type,
       status
  from user_objects
 where object_name like 'OF\_%' escape '\'
   and object_name not like 'BIN$%'
   and status <> 'VALID'
 order by object_type, object_name;

--------------------------------------------------------------------------------
-- 04. Required explicit indexes
-- Expected result: no rows selected.
--------------------------------------------------------------------------------

with expected_indexes (index_name) as (
  select 'OF_USERS_USERNAME_UIX' from dual union all
  select 'OF_USERS_EMAIL_UIX' from dual union all
  select 'OF_DEPARTMENTS_MANAGER_IX' from dual union all
  select 'OF_USERS_DEPARTMENT_IX' from dual union all
  select 'OF_USERS_MANAGER_IX' from dual union all
  select 'OF_USERS_LOCATION_IX' from dual union all
  select 'OF_USER_ROLES_ROLE_IX' from dual union all
  select 'OF_USER_ROLES_GRANTED_BY_IX' from dual union all
  select 'OF_USER_ROLES_REVOKED_BY_IX' from dual union all
  select 'OF_AUDIT_ACTOR_IX' from dual union all
  select 'OF_AUDIT_ENTITY_IX' from dual union all
  select 'OF_AUDIT_CORRELATION_IX' from dual union all
  select 'OF_ERROR_ACTOR_IX' from dual union all
  select 'OF_ERROR_OCCURRED_IX' from dual union all
  select 'OF_NOTIFICATIONS_RECIPIENT_IX' from dual union all
  select 'OF_NOTIFICATIONS_ENTITY_IX' from dual union all
  select 'OF_CATEGORIES_OWNER_DEPT_IX' from dual union all
  select 'OF_CATEGORIES_PRIORITY_IX' from dual union all
  select 'OF_SLA_POLICIES_PRIORITY_IX' from dual union all
  select 'OF_TICKETS_REQUESTER_STATUS_IX' from dual union all
  select 'OF_TICKETS_REQUESTER_DEPT_IX' from dual union all
  select 'OF_TICKETS_AGENT_STATUS_IX' from dual union all
  select 'OF_TICKETS_CATEGORY_STATUS_IX' from dual union all
  select 'OF_TICKETS_SLA_DUE_IX' from dual union all
  select 'OF_TICKETS_PRIORITY_IX' from dual union all
  select 'OF_TICKETS_SLA_POLICY_IX' from dual union all
  select 'OF_TICKETS_LOCATION_IX' from dual union all
  select 'OF_COMMENTS_TICKET_TIME_IX' from dual union all
  select 'OF_COMMENTS_AUTHOR_IX' from dual union all
  select 'OF_HISTORY_TICKET_TIME_IX' from dual union all
  select 'OF_HISTORY_CHANGED_BY_IX' from dual union all
  select 'OF_HISTORY_CORRELATION_IX' from dual union all
  select 'OF_PAUSES_ONE_ACTIVE_UIX' from dual union all
  select 'OF_PAUSES_TICKET_STARTED_IX' from dual union all
  select 'OF_PAUSES_STARTED_BY_IX' from dual union all
  select 'OF_PAUSES_ENDED_BY_IX' from dual union all
  select 'OF_SLA_EVENTS_NOTIFICATION_IX' from dual union all
  select 'OF_SLA_EVENTS_STATUS_IX' from dual
)
select index_name as missing_index
  from expected_indexes
minus
select index_name
  from user_indexes;

--------------------------------------------------------------------------------
-- 05. Actual row counts
-- Expected after installation and the rollback-safe P02 tests: every count is 0.
--------------------------------------------------------------------------------

select 'OF_APP_SETTINGS' table_name, count(*) row_count from of_app_settings
union all select 'OF_APP_USERS', count(*) from of_app_users
union all select 'OF_AUDIT_LOG', count(*) from of_audit_log
union all select 'OF_DEPARTMENTS', count(*) from of_departments
union all select 'OF_ERROR_LOG', count(*) from of_error_log
union all select 'OF_LOCATIONS', count(*) from of_locations
union all select 'OF_NOTIFICATIONS', count(*) from of_notifications
union all select 'OF_PRIORITIES', count(*) from of_priorities
union all select 'OF_ROLES', count(*) from of_roles
union all select 'OF_SERVICE_CATEGORIES', count(*) from of_service_categories
union all select 'OF_SLA_EVENTS', count(*) from of_sla_events
union all select 'OF_SLA_POLICIES', count(*) from of_sla_policies
union all select 'OF_TICKET_COMMENTS', count(*) from of_ticket_comments
union all select 'OF_TICKET_SLA_PAUSES', count(*) from of_ticket_sla_pauses
union all select 'OF_TICKET_STATUS_HISTORY', count(*) from of_ticket_status_history
union all select 'OF_TICKETS', count(*) from of_tickets
union all select 'OF_USER_ROLES', count(*) from of_user_roles
order by table_name;

--------------------------------------------------------------------------------
-- End P02 validator. All PASS values, empty exception reports, and zero row
-- counts are required before P02 is accepted.
--------------------------------------------------------------------------------
