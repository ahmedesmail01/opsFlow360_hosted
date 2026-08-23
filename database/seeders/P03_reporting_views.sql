--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P03 - Initial Reporting Views
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Creates/Replaces: 5 explicitly read-only views
-- Prerequisite: P02 schema and both P03 seed scripts
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 01. One denormalized row per ticket for reports and future APEX regions
--------------------------------------------------------------------------------

create or replace view of_v_ticket_details as
select t.id ticket_id,
       t.ticket_no,
       t.status_code,
       t.source_code,
       t.subject,
       t.description,
       t.requester_user_id,
       requester.username requester_username,
       requester.display_name requester_display_name,
       t.requester_department_id,
       requester_department.code requester_department_code,
       requester_department.name requester_department_name,
       t.category_id,
       category.code category_code,
       category.name category_name,
       owner_department.code owner_department_code,
       owner_department.name owner_department_name,
       t.priority_id,
       priority.code priority_code,
       priority.name priority_name,
       priority.severity_rank,
       t.location_id,
       location.code location_code,
       location.name location_name,
       t.assigned_agent_user_id,
       agent.username assigned_agent_username,
       agent.display_name assigned_agent_name,
       t.sla_policy_id,
       policy.response_minutes,
       policy.resolution_minutes,
       t.submitted_at,
       t.triaged_at,
       t.first_responded_at,
       t.response_due_at,
       t.resolution_due_at,
       t.waiting_started_at,
       t.resolved_at,
       t.closed_at,
       t.cancelled_at,
       t.resolution_summary,
       t.closure_reason,
       t.row_version,
       t.created_at,
       t.updated_at,
       case
         when t.status_code in ('RESOLVED', 'CLOSED', 'REJECTED', 'CANCELLED')
           then 'N'
         else 'Y'
       end is_open,
       case
         when t.status_code in ('REJECTED', 'CANCELLED') then 'NOT_APPLICABLE'
         when t.response_due_at is null then 'NO_SLA'
         when t.first_responded_at is not null
              and t.first_responded_at <= t.response_due_at then 'MET'
         when t.first_responded_at is not null
              and t.first_responded_at > t.response_due_at then 'LATE'
         when t.response_due_at < systimestamp then 'BREACHED'
         when t.response_due_at <= systimestamp + numtodsinterval(60, 'MINUTE')
           then 'AT_RISK'
         else 'ON_TRACK'
       end response_health_code,
       case
         when t.status_code in ('REJECTED', 'CANCELLED') then 'NOT_APPLICABLE'
         when t.resolution_due_at is null then 'NO_SLA'
         when t.resolved_at is not null
              and t.resolved_at <= t.resolution_due_at then 'MET'
         when t.resolved_at is not null
              and t.resolved_at > t.resolution_due_at then 'LATE'
         when t.resolution_due_at < systimestamp then 'BREACHED'
         when t.resolution_due_at <= systimestamp + numtodsinterval(120, 'MINUTE')
           then 'AT_RISK'
         else 'ON_TRACK'
       end resolution_health_code,
       case
         when t.resolution_due_at is null then null
         else round((cast(t.resolution_due_at as date) - sysdate) * 1440)
       end minutes_to_resolution_due,
       round(
         (sysdate - cast(coalesce(t.submitted_at, t.created_at) as date)) * 24,
         2
       ) age_hours
  from of_tickets t
  join of_app_users requester
    on requester.id = t.requester_user_id
  join of_departments requester_department
    on requester_department.id = t.requester_department_id
  join of_service_categories category
    on category.id = t.category_id
  join of_departments owner_department
    on owner_department.id = category.owner_department_id
  join of_priorities priority
    on priority.id = t.priority_id
  left join of_locations location
    on location.id = t.location_id
  left join of_app_users agent
    on agent.id = t.assigned_agent_user_id
  left join of_sla_policies policy
    on policy.id = t.sla_policy_id
with read only constraint of_v_ticket_details_ro;

comment on table of_v_ticket_details is
  'Read-only joined ticket facts with response/resolution SLA classifications.';

--------------------------------------------------------------------------------
-- 02. Prioritized live SLA queue using analytic functions
--------------------------------------------------------------------------------

create or replace view of_v_sla_queue as
select d.ticket_id,
       d.ticket_no,
       d.subject,
       d.status_code,
       d.category_code,
       d.category_name,
       d.priority_code,
       d.priority_name,
       d.severity_rank,
       d.requester_display_name,
       d.assigned_agent_name,
       d.response_due_at,
       d.resolution_due_at,
       d.response_health_code,
       d.resolution_health_code,
       d.minutes_to_resolution_due,
       row_number() over (
         order by
           case d.resolution_health_code
             when 'BREACHED' then 1
             when 'AT_RISK' then 2
             when 'ON_TRACK' then 3
             else 4
           end,
           d.resolution_due_at,
           d.severity_rank,
           d.ticket_id
       ) queue_rank,
       count(*) over (
         partition by d.resolution_health_code
       ) health_group_count
  from of_v_ticket_details d
 where d.is_open = 'Y'
   and d.resolution_due_at is not null
with read only constraint of_v_sla_queue_ro;

comment on table of_v_sla_queue is
  'Open SLA-backed tickets ranked by breach risk, deadline, severity, and ID.';

--------------------------------------------------------------------------------
-- 03. Category-level dashboard aggregates
--------------------------------------------------------------------------------

create or replace view of_v_service_dashboard as
select c.id category_id,
       c.code category_code,
       c.name category_name,
       d.code owner_department_code,
       d.name owner_department_name,
       count(td.ticket_id) total_tickets,
       sum(case when td.is_open = 'Y' then 1 else 0 end) open_tickets,
       sum(case when td.status_code = 'WAITING_USER' then 1 else 0 end)
         waiting_user_tickets,
       sum(case when td.status_code = 'RESOLVED' then 1 else 0 end)
         resolved_tickets,
       sum(case when td.status_code = 'CLOSED' then 1 else 0 end)
         closed_tickets,
       sum(case when td.resolution_health_code = 'BREACHED' then 1 else 0 end)
         breached_tickets,
       sum(case when td.resolution_health_code = 'AT_RISK' then 1 else 0 end)
         at_risk_tickets,
       round(
         avg(
           case
             when td.resolved_at is not null and td.submitted_at is not null
               then (cast(td.resolved_at as date) - cast(td.submitted_at as date)) * 24
           end
         ),
         2
       ) avg_resolution_hours
  from of_service_categories c
  join of_departments d
    on d.id = c.owner_department_id
  left join of_v_ticket_details td
    on td.category_id = c.id
 group by c.id, c.code, c.name, d.code, d.name
with read only constraint of_v_service_dashboard_ro;

comment on table of_v_service_dashboard is
  'One dashboard row per service category including zero-ticket categories.';

--------------------------------------------------------------------------------
-- 04. User and active-role summary using LISTAGG
--------------------------------------------------------------------------------

create or replace view of_v_user_access as
select u.id user_id,
       u.username,
       u.email,
       u.display_name,
       d.code department_code,
       d.name department_name,
       l.code location_code,
       u.locale_code,
       u.timezone_name,
       u.is_active,
       count(r.id) active_role_count,
       listagg(r.code, ', ') within group (order by r.code) active_role_codes
  from of_app_users u
  join of_departments d
    on d.id = u.department_id
  left join of_locations l
    on l.id = u.location_id
  left join of_user_roles ur
    on ur.user_id = u.id
   and ur.is_active = 'Y'
  left join of_roles r
    on r.id = ur.role_id
   and r.is_active = 'Y'
 group by u.id, u.username, u.email, u.display_name,
          d.code, d.name, l.code, u.locale_code, u.timezone_name, u.is_active
with read only constraint of_v_user_access_ro;

comment on table of_v_user_access is
  'Read-only user profile with a deterministic ordered list of active roles.';

--------------------------------------------------------------------------------
-- 05. Unified ticket timeline using UNION ALL
--------------------------------------------------------------------------------

create or replace view of_v_ticket_timeline as
select tk.id ticket_id,
       tk.ticket_no,
       h.id event_id,
       'STATUS' event_type_code,
       h.changed_at event_at,
       h.changed_by_user_id actor_user_id,
       h.changed_by actor_name,
       'PUBLIC' visibility_code,
       case
         when h.from_status_code is null
           then 'CREATED -> ' || h.to_status_code
         else h.from_status_code || ' -> ' || h.to_status_code
       end event_summary,
       h.reason_text event_detail
  from of_ticket_status_history h
  join of_tickets tk on tk.id = h.ticket_id
union all
select tk.id,
       tk.ticket_no,
       c.id,
       'COMMENT',
       c.created_at,
       c.author_user_id,
       coalesce(u.display_name, 'SYSTEM'),
       c.visibility_code,
       case c.is_system_generated
         when 'Y' then 'System note'
         else 'Comment by ' || coalesce(u.display_name, 'Unknown user')
       end,
       dbms_lob.substr(c.comment_text, 4000, 1)
  from of_ticket_comments c
  join of_tickets tk on tk.id = c.ticket_id
  left join of_app_users u on u.id = c.author_user_id
union all
select tk.id,
       tk.ticket_no,
       p.id,
       'SLA_PAUSE',
       p.started_at,
       p.started_by_user_id,
       u.display_name,
       'INTERNAL',
       case when p.ended_at is null then 'SLA pause started'
            else 'SLA pause completed' end,
       p.reason_code
  from of_ticket_sla_pauses p
  join of_tickets tk on tk.id = p.ticket_id
  join of_app_users u on u.id = p.started_by_user_id
union all
select tk.id,
       tk.ticket_no,
       e.id,
       'SLA_EVENT',
       e.detected_at,
       cast(null as number),
       'SYSTEM',
       'INTERNAL',
       e.event_type_code,
       e.status_code || ' at stored deadline snapshot'
  from of_sla_events e
  join of_tickets tk on tk.id = e.ticket_id
with read only constraint of_v_ticket_timeline_ro;

comment on table of_v_ticket_timeline is
  'Unified read-only status, comment, SLA-pause, and SLA-event chronology.';

--------------------------------------------------------------------------------
-- 06. Completion summary
--------------------------------------------------------------------------------

select object_name view_name,
       status
  from user_objects
 where object_type = 'VIEW'
   and object_name in (
     'OF_V_TICKET_DETAILS', 'OF_V_SLA_QUEUE', 'OF_V_SERVICE_DASHBOARD',
     'OF_V_USER_ACCESS', 'OF_V_TICKET_TIMELINE'
   )
 order by object_name;

--------------------------------------------------------------------------------
-- Expected: 5 rows, every STATUS = VALID.
--------------------------------------------------------------------------------
