--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P09 - Employee Self-Service Read Models
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Creates: 5 explicitly read-only, current-user-filtered views
-- Safety: Requires accepted P08 database objects and manual APEX export gate.
-- Rerun: Refuses a mixed/partial install. Validate or roll back before retrying.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. P08 acceptance-state database preflight
-- Manual gate still required: complete P08 checklist and saved APEX export.
--------------------------------------------------------------------------------

declare
  l_apex_object_count number;
  l_code_count        number;
  l_base_count        number;
  l_bootstrap_count   number;
  l_collision_count   number;
begin
  select count(*)
    into l_apex_object_count
    from user_objects
   where object_name = 'OF_APEX_API'
     and object_type in ('PACKAGE', 'PACKAGE BODY')
     and status = 'VALID';

  select count(*)
    into l_code_count
    from user_objects
   where object_name in (
     'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
     'OF_AUDIT_LOG_GUARD_TRG', 'OF_TICKET_API',
     'OF_TICKET_HISTORY_GUARD_TRG', 'OF_ASSET_API',
     'OF_ASSET_HISTORY_GUARD_TRG', 'OF_PROCUREMENT_API',
     'OF_INVENTORY_API', 'OF_STOCK_MOVEMENT_GUARD_TRG', 'OF_APEX_API'
   )
     and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
     and status = 'VALID';

  select count(*)
    into l_base_count
    from user_objects
   where object_name in (
     'OF_TICKETS', 'OF_TICKET_COMMENTS', 'OF_TICKET_STATUS_HISTORY',
     'OF_ASSETS', 'OF_ASSET_ASSIGNMENTS', 'OF_ASSET_TYPES',
     'OF_PURCHASE_REQUESTS', 'OF_PURCHASE_REQUEST_ITEMS',
     'OF_V_TICKET_DETAILS', 'OF_V_TICKET_TIMELINE'
   )
     and object_type in ('TABLE', 'VIEW')
     and status = 'VALID';

  select count(*)
    into l_bootstrap_count
    from of_app_users u
   where u.created_by = 'P08_BOOTSTRAP'
     and u.is_active = 'Y'
     and exists (
       select 1
         from of_user_roles ur
         join of_roles r
           on r.id = ur.role_id
          and r.is_active = 'Y'
        where ur.user_id = u.id
          and ur.is_active = 'Y'
          and r.code = 'EMPLOYEE'
     );

  select count(*)
    into l_collision_count
    from user_objects
   where object_name in (
     'OF_V_MY_TICKETS', 'OF_V_MY_TICKET_TIMELINE', 'OF_V_MY_ASSETS',
     'OF_V_MY_PURCHASE_REQUESTS', 'OF_V_MY_PURCHASE_REQUEST_ITEMS'
   );

  if l_apex_object_count <> 2 then
    raise_application_error(
      -20500,
      'P09 stopped: expected valid OF_APEX_API package and body; found ' ||
      l_apex_object_count || '.'
    );
  end if;

  if l_code_count <> 22 then
    raise_application_error(
      -20501,
      'P09 stopped: expected 22 valid P04-P08 code objects; found ' ||
      l_code_count || '.'
    );
  end if;

  if l_base_count <> 10 then
    raise_application_error(
      -20502,
      'P09 stopped: expected 10 valid ticket/asset/procurement read-model ' ||
      'dependencies; found ' || l_base_count || '.'
    );
  end if;

  if l_bootstrap_count <> 1 then
    raise_application_error(
      -20503,
      'P09 stopped: expected exactly one active P08 bootstrap employee; found ' ||
      l_bootstrap_count || '. Restore the P08 bootstrap roles first.'
    );
  end if;

  if l_collision_count <> 0 then
    raise_application_error(
      -20504,
      'P09 stopped: ' || l_collision_count ||
      ' P09 view(s) already exist. Validate or run the guarded P09 rollback; ' ||
      'do not mix installations.'
    );
  end if;

  dbms_output.put_line(
    'P09 database preflight passed. Manual P08 APEX acceptance/export gate ' ||
    'remains required.'
  );
end;
/

--------------------------------------------------------------------------------
-- 01. Employee-owned ticket list and detail source
--------------------------------------------------------------------------------

create or replace view of_v_my_tickets as
select d.ticket_id,
       d.ticket_no,
       d.status_code,
       d.source_code,
       d.subject,
       d.description,
       d.requester_user_id,
       d.requester_display_name,
       d.requester_department_name,
       d.category_id,
       d.category_code,
       d.category_name,
       d.priority_id,
       d.priority_code,
       d.priority_name,
       d.location_id,
       d.location_code,
       d.location_name,
       d.assigned_agent_name,
       d.submitted_at,
       d.response_due_at,
       d.resolution_due_at,
       d.resolved_at,
       d.closed_at,
       d.cancelled_at,
       d.resolution_summary,
       d.closure_reason,
       d.row_version,
       d.created_at,
       d.updated_at,
       d.is_open,
       d.response_health_code,
       d.resolution_health_code,
       d.minutes_to_resolution_due,
       d.age_hours
  from of_v_ticket_details d
 where d.requester_user_id = of_security_api.current_user_id()
   and exists (
     select 1
       from of_user_roles ur
       join of_roles r
         on r.id = ur.role_id
        and r.is_active = 'Y'
      where ur.user_id = of_security_api.current_user_id()
        and ur.is_active = 'Y'
        and r.code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
   )
with read only constraint of_v_my_tickets_ro;

comment on table of_v_my_tickets is
  'P09 current-user ticket source. Returns only tickets owned by the mapped self-service actor.';

--------------------------------------------------------------------------------
-- 02. Public-only timeline for employee-owned tickets
--------------------------------------------------------------------------------

create or replace view of_v_my_ticket_timeline as
select tl.ticket_id,
       tl.ticket_no,
       tl.event_id,
       tl.event_type_code,
       tl.event_at,
       tl.actor_user_id,
       tl.actor_name,
       tl.visibility_code,
       tl.event_summary,
       tl.event_detail
  from of_v_ticket_timeline tl
  join of_v_my_tickets mt
    on mt.ticket_id = tl.ticket_id
 where tl.visibility_code = 'PUBLIC'
with read only constraint of_v_my_ticket_timeline_ro;

comment on table of_v_my_ticket_timeline is
  'P09 public timeline for current-user tickets. Internal comments and SLA events are excluded.';

--------------------------------------------------------------------------------
-- 03. Active assets assigned to the current self-service actor
--------------------------------------------------------------------------------

create or replace view of_v_my_assets as
select aa.id assignment_id,
       aa.assigned_to_user_id,
       aa.assigned_at,
       aa.condition_out_code,
       aa.notes assignment_notes,
       a.id asset_id,
       a.asset_tag,
       a.asset_name,
       a.description asset_description,
       a.serial_number,
       a.status_code asset_status_code,
       atp.id asset_type_id,
       atp.code asset_type_code,
       atp.name asset_type_name,
       l.id location_id,
       l.code location_code,
       l.name location_name,
       a.acquisition_date,
       a.warranty_end_date,
       a.row_version asset_row_version
  from of_asset_assignments aa
  join of_assets a
    on a.id = aa.asset_id
  join of_asset_types atp
    on atp.id = a.asset_type_id
  join of_locations l
    on l.id = a.current_location_id
 where aa.assigned_to_user_id = of_security_api.current_user_id()
   and aa.returned_at is null
   and exists (
     select 1
       from of_user_roles ur
       join of_roles r
         on r.id = ur.role_id
        and r.is_active = 'Y'
      where ur.user_id = of_security_api.current_user_id()
        and ur.is_active = 'Y'
        and r.code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
   )
with read only constraint of_v_my_assets_ro;

comment on table of_v_my_assets is
  'P09 active asset assignments for the mapped current self-service actor.';

--------------------------------------------------------------------------------
-- 04. Employee-owned purchase-request header source
--------------------------------------------------------------------------------

create or replace view of_v_my_purchase_requests as
select pr.id request_id,
       pr.request_no,
       pr.requester_user_id,
       pr.requester_department_id,
       d.code requester_department_code,
       d.name requester_department_name,
       pr.status_code,
       pr.business_justification,
       pr.currency_code,
       pr.total_amount,
       (select count(*)
          from of_purchase_request_items pri
         where pri.purchase_request_id = pr.id) item_count,
       (select coalesce(sum(pri.line_total), 0)
          from of_purchase_request_items pri
         where pri.purchase_request_id = pr.id) calculated_total_amount,
       pr.submitted_at,
       pr.approved_at,
       pr.closed_at,
       pr.cancellation_reason,
       pr.row_version,
       pr.created_at,
       pr.updated_at
  from of_purchase_requests pr
  join of_departments d
    on d.id = pr.requester_department_id
 where pr.requester_user_id = of_security_api.current_user_id()
   and exists (
     select 1
       from of_user_roles ur
       join of_roles r
         on r.id = ur.role_id
        and r.is_active = 'Y'
      where ur.user_id = of_security_api.current_user_id()
        and ur.is_active = 'Y'
        and r.code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
   )
with read only constraint of_v_my_purchase_requests_ro;

comment on table of_v_my_purchase_requests is
  'P09 current-user purchase-request headers with server-calculated item totals.';

--------------------------------------------------------------------------------
-- 05. Employee-owned purchase-request item source
--------------------------------------------------------------------------------

create or replace view of_v_my_purchase_request_items as
select pri.id request_item_id,
       pri.purchase_request_id request_id,
       pr.request_no,
       pr.requester_user_id,
       pr.status_code request_status_code,
       pr.row_version request_row_version,
       pr.currency_code,
       pri.line_no,
       pri.catalog_item_id,
       ci.code catalog_item_code,
       ci.name catalog_item_name,
       pri.item_description,
       pri.quantity,
       pri.estimated_unit_price,
       pri.line_total,
       pri.required_by_date,
       pri.created_at,
       pri.updated_at
  from of_purchase_request_items pri
  join of_purchase_requests pr
    on pr.id = pri.purchase_request_id
  left join of_catalog_items ci
    on ci.id = pri.catalog_item_id
 where pr.requester_user_id = of_security_api.current_user_id()
   and exists (
     select 1
       from of_user_roles ur
       join of_roles r
         on r.id = ur.role_id
        and r.is_active = 'Y'
      where ur.user_id = of_security_api.current_user_id()
        and ur.is_active = 'Y'
        and r.code in ('EMPLOYEE', 'OPERATIONS_ADMIN')
   )
with read only constraint of_v_my_pr_items_ro;

comment on table of_v_my_purchase_request_items is
  'P09 current-user purchase-request lines. Header ownership is rechecked on every query.';

--------------------------------------------------------------------------------
-- 06. Immediate object-health result
-- Expected: 5 rows, all VALID.
--------------------------------------------------------------------------------

select object_name,
       object_type,
       status
  from user_objects
 where object_name in (
   'OF_V_MY_TICKETS', 'OF_V_MY_TICKET_TIMELINE', 'OF_V_MY_ASSETS',
   'OF_V_MY_PURCHASE_REQUESTS', 'OF_V_MY_PURCHASE_REQUEST_ITEMS'
 )
 order by object_name;

--------------------------------------------------------------------------------
-- End P09 installer. Expected SQL Scripts statements: 12.
--------------------------------------------------------------------------------
