--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P03 - Seed and Reporting View Validation
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Safety: Read-only.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. P02 prerequisite and P03 view inventory
--------------------------------------------------------------------------------

select 'P02_TABLE_COUNT' check_name,
       count(*) actual_value,
       17 expected_value,
       case when count(*) = 17 then 'PASS' else 'FAIL' end result
  from user_tables
 where table_name in (
   'OF_DEPARTMENTS', 'OF_LOCATIONS', 'OF_APP_USERS', 'OF_ROLES',
   'OF_USER_ROLES', 'OF_APP_SETTINGS', 'OF_AUDIT_LOG', 'OF_ERROR_LOG',
   'OF_NOTIFICATIONS', 'OF_PRIORITIES', 'OF_SERVICE_CATEGORIES',
   'OF_SLA_POLICIES', 'OF_TICKETS', 'OF_TICKET_COMMENTS',
   'OF_TICKET_STATUS_HISTORY', 'OF_TICKET_SLA_PAUSES', 'OF_SLA_EVENTS'
 );

select 'P03_VALID_VIEW_COUNT' check_name,
       count(*) actual_value,
       5 expected_value,
       case when count(*) = 5 then 'PASS' else 'FAIL' end result
  from user_objects
 where object_type = 'VIEW'
   and status = 'VALID'
   and object_name in (
     'OF_V_TICKET_DETAILS', 'OF_V_SLA_QUEUE', 'OF_V_SERVICE_DASHBOARD',
     'OF_V_USER_ACCESS', 'OF_V_TICKET_TIMELINE'
   );

--------------------------------------------------------------------------------
-- 02. Reference counts
--------------------------------------------------------------------------------

select 'DEPARTMENTS' entity_name, count(*) actual_value, 6 expected_value,
       case when count(*) = 6 then 'PASS' else 'FAIL' end result
  from of_departments
 where code in ('EXEC', 'IT', 'HR', 'FIN', 'PROC', 'FAC')
union all
select 'LOCATIONS', count(*), 4,
       case when count(*) = 4 then 'PASS' else 'FAIL' end
  from of_locations
 where code in ('CAI-HQ', 'CAI-WH', 'ALX-OFFICE', 'DXB-OFFICE')
union all
select 'ROLES', count(*), 6,
       case when count(*) = 6 then 'PASS' else 'FAIL' end
  from of_roles
union all
select 'APP_SETTINGS', count(*), 5,
       case when count(*) = 5 then 'PASS' else 'FAIL' end
  from of_app_settings
 where setting_code in (
   'DEFAULT_LOCALE', 'DEFAULT_TIMEZONE', 'TICKET_PREFIX',
   'SLA_WARNING_PERCENT', 'ENABLE_EMAIL_NOTIFICATIONS'
 )
union all
select 'PRIORITIES', count(*), 4,
       case when count(*) = 4 then 'PASS' else 'FAIL' end
  from of_priorities
 where code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
union all
select 'SERVICE_CATEGORIES', count(*), 6,
       case when count(*) = 6 then 'PASS' else 'FAIL' end
  from of_service_categories
 where code in (
   'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
   'NETWORK', 'FACILITIES', 'HR_REQUEST'
 )
union all
select 'SLA_POLICIES', count(*), 24,
       case when count(*) = 24 then 'PASS' else 'FAIL' end
  from of_sla_policies sp
  join of_service_categories c on c.id = sp.category_id
  join of_priorities p on p.id = sp.priority_id
 where c.code in (
   'ACCOUNT_ACCESS', 'EMAIL_SUPPORT', 'HARDWARE',
   'NETWORK', 'FACILITIES', 'HR_REQUEST'
 )
   and p.code in ('CRITICAL', 'HIGH', 'MEDIUM', 'LOW')
   and sp.effective_from = date '2026-01-01'
order by entity_name;

--------------------------------------------------------------------------------
-- 03. Demo counts
--------------------------------------------------------------------------------

select 'DEMO_USERS' entity_name, count(*) actual_value, 12 expected_value,
       case when count(*) = 12 then 'PASS' else 'FAIL' end result
  from of_app_users
 where username in (
   'admin.ops', 'amira.manager', 'omar.agent', 'salma.agent',
   'layla.employee', 'youssef.employee', 'mariam.employee',
   'kareem.manager', 'nader.proc', 'farah.auditor',
   'hassan.facility', 'nadia.hr'
 )
union all
select 'ACTIVE_ROLE_GRANTS', count(*), 24,
       case when count(*) = 24 then 'PASS' else 'FAIL' end
  from of_user_roles ur
  join of_app_users u on u.id = ur.user_id
 where u.username in (
   'admin.ops', 'amira.manager', 'omar.agent', 'salma.agent',
   'layla.employee', 'youssef.employee', 'mariam.employee',
   'kareem.manager', 'nader.proc', 'farah.auditor',
   'hassan.facility', 'nadia.hr'
 )
   and ur.is_active = 'Y'
union all
select 'DEMO_TICKETS', count(*), 12,
       case when count(*) = 12 then 'PASS' else 'FAIL' end
  from of_tickets where ticket_no like 'TKT-DEMO-%'
union all
select 'DEMO_COMMENTS', count(*), 10,
       case when count(*) = 10 then 'PASS' else 'FAIL' end
  from of_ticket_comments c
  join of_tickets t on t.id = c.ticket_id
 where t.ticket_no like 'TKT-DEMO-%'
   and c.created_by like 'P03_CMT_%'
union all
select 'DEMO_HISTORY', count(*), 23,
       case when count(*) = 23 then 'PASS' else 'FAIL' end
  from of_ticket_status_history
 where correlation_id like 'P03-HIST-%'
union all
select 'DEMO_ACTIVE_PAUSES', count(*), 1,
       case when count(*) = 1 then 'PASS' else 'FAIL' end
  from of_ticket_sla_pauses p
  join of_tickets t on t.id = p.ticket_id
 where t.ticket_no = 'TKT-DEMO-0005'
   and p.ended_at is null
union all
select 'DEMO_NOTIFICATIONS', count(*), 3,
       case when count(*) = 3 then 'PASS' else 'FAIL' end
  from of_notifications
 where idempotency_key like 'P03-NOTIFY-%'
union all
select 'DEMO_SLA_EVENTS', count(*), 2,
       case when count(*) = 2 then 'PASS' else 'FAIL' end
  from of_sla_events
 where correlation_id like 'P03-SLA-EVENT-%'
union all
select 'DEMO_AUDIT_ROWS', count(*), 12,
       case when count(*) = 12 then 'PASS' else 'FAIL' end
  from of_audit_log
 where correlation_id like 'P03-AUDIT-%'
union all
select 'DEMO_ERROR_ROWS', count(*), 1,
       case when count(*) = 1 then 'PASS' else 'FAIL' end
  from of_error_log
 where correlation_id = 'P03-DEMO-ERROR-0001'
order by entity_name;

--------------------------------------------------------------------------------
-- 04. Lifecycle coverage
--------------------------------------------------------------------------------

select status_code,
       count(*) ticket_count
  from of_tickets
 where ticket_no like 'TKT-DEMO-%'
 group by status_code
 order by status_code;

select 'DISTINCT_DEMO_STATUSES' check_name,
       count(distinct status_code) actual_value,
       9 expected_value,
       case when count(distinct status_code) = 9 then 'PASS' else 'FAIL' end result
  from of_tickets
 where ticket_no like 'TKT-DEMO-%';

--------------------------------------------------------------------------------
-- 05. Duplicate and privacy exception reports
-- Expected result for each query: no rows.
--------------------------------------------------------------------------------

select upper(username) duplicate_username,
       count(*) duplicate_count
  from of_app_users
 group by upper(username)
having count(*) > 1;

select ticket_no,
       count(*) duplicate_count
  from of_tickets
 where ticket_no like 'TKT-DEMO-%'
 group by ticket_no
having count(*) > 1;

select user_id,
       role_id,
       count(*) duplicate_count
  from of_user_roles
 group by user_id, role_id
having count(*) > 1;

select username,
       email
  from of_app_users
 where username in (
   'admin.ops', 'amira.manager', 'omar.agent', 'salma.agent',
   'layla.employee', 'youssef.employee', 'mariam.employee',
   'kareem.manager', 'nader.proc', 'farah.auditor',
   'hassan.facility', 'nadia.hr'
 )
   and email not like '%@example.invalid';

--------------------------------------------------------------------------------
-- 06. Reporting reconciliation
--------------------------------------------------------------------------------

select 'DETAIL_VIEW_TICKETS' check_name,
       (select count(*) from of_v_ticket_details
         where ticket_no like 'TKT-DEMO-%') actual_value,
       12 expected_value,
       case when (select count(*) from of_v_ticket_details
                   where ticket_no like 'TKT-DEMO-%') = 12
            then 'PASS' else 'FAIL' end result
  from dual
union all
select 'SLA_QUEUE_TICKETS',
       (select count(*) from of_v_sla_queue
         where ticket_no like 'TKT-DEMO-%'),
       7,
       case when (select count(*) from of_v_sla_queue
                   where ticket_no like 'TKT-DEMO-%') = 7
            then 'PASS' else 'FAIL' end
  from dual
union all
select 'DASHBOARD_CATEGORIES',
       (select count(*) from of_v_service_dashboard),
       6,
       case when (select count(*) from of_v_service_dashboard) = 6
            then 'PASS' else 'FAIL' end
  from dual
union all
select 'USER_ACCESS_ROWS',
       (select count(*) from of_v_user_access
         where email like '%@example.invalid'),
       12,
       case when (select count(*) from of_v_user_access
                   where email like '%@example.invalid') = 12
            then 'PASS' else 'FAIL' end
  from dual
union all
select 'TIMELINE_EVENTS',
       (select count(*) from of_v_ticket_timeline
         where ticket_no like 'TKT-DEMO-%'),
       36,
       case when (select count(*) from of_v_ticket_timeline
                   where ticket_no like 'TKT-DEMO-%') = 36
            then 'PASS' else 'FAIL' end
  from dual
order by check_name;

select 'DASHBOARD_TICKET_RECONCILIATION' check_name,
       (select sum(total_tickets) from of_v_service_dashboard) dashboard_total,
       (select count(*) from of_tickets) base_total,
       case
         when (select sum(total_tickets) from of_v_service_dashboard) =
              (select count(*) from of_tickets)
           then 'PASS'
         else 'FAIL'
       end result
  from dual;

select 'USER_ROLE_RECONCILIATION' check_name,
       (select sum(active_role_count) from of_v_user_access
         where email like '%@example.invalid') view_total,
       (select count(*)
          from of_user_roles ur
          join of_app_users u on u.id = ur.user_id
         where u.email like '%@example.invalid'
           and ur.is_active = 'Y') base_total,
       case
         when (select sum(active_role_count) from of_v_user_access
                where email like '%@example.invalid') =
              (select count(*)
                 from of_user_roles ur
                 join of_app_users u on u.id = ur.user_id
                where u.email like '%@example.invalid'
                  and ur.is_active = 'Y')
           then 'PASS'
         else 'FAIL'
       end result
  from dual;

--------------------------------------------------------------------------------
-- 07. Object health exception report
-- Expected: no rows.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name like 'OF\_%' escape '\'
   and object_name not like 'BIN$%'
   and status <> 'VALID'
 order by object_type, object_name;

--------------------------------------------------------------------------------
-- End P03 validator. Every explicit RESULT must be PASS and every exception
-- report must return no rows.
--------------------------------------------------------------------------------
