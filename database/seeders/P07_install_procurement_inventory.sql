--------------------------------------------------------------------------------
-- OpsFlow 360
-- Patch: P07 - Procurement, Receiving, and Inventory API
-- Target: Oracle APEX SQL Workshop -> SQL Scripts
-- Creates: 11 tables, 2 package specifications/bodies, 1 ledger guard trigger
-- Safety: P06 must be valid; no P07 object may already exist.
-- Transaction: Reference seed commits; business APIs never commit.
-- Important: Oracle DDL commits. Reject any run whose Summary has an error.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 00. Entry gate and physical procurement/inventory schema
--------------------------------------------------------------------------------

declare
  l_base_count       number;
  l_dependency_count number;
  l_p06_type_count   number;
  l_p06_drift_count  number;
  l_deferred_count   number;
  l_collision_count  number;

  procedure run_ddl(p_sql in varchar2) is
  begin
    execute immediate p_sql;
  end run_ddl;
begin
  select count(*) into l_base_count
    from user_tables
   where table_name in (
     'OF_DEPARTMENTS', 'OF_LOCATIONS', 'OF_APP_USERS', 'OF_ROLES',
     'OF_USER_ROLES', 'OF_APP_SETTINGS', 'OF_AUDIT_LOG',
     'OF_ASSET_TYPES', 'OF_ASSETS', 'OF_ASSET_REPAIRS'
   );

  select count(*) into l_dependency_count
    from user_objects
   where object_name in (
     'OF_UTIL_API', 'OF_SECURITY_API', 'OF_AUDIT_API', 'OF_ERROR_API',
     'OF_AUDIT_LOG_GUARD_TRG', 'OF_TICKET_API',
     'OF_TICKET_HISTORY_GUARD_TRG', 'OF_ASSET_API',
     'OF_ASSET_HISTORY_GUARD_TRG'
   )
     and object_type in ('PACKAGE', 'PACKAGE BODY', 'TRIGGER')
     and status = 'VALID';

  execute immediate q'~
    select count(*) from of_asset_types
     where code in (
       'LAPTOP', 'DESKTOP', 'MONITOR',
       'MOBILE_PHONE', 'PRINTER', 'FURNITURE'
     ) and is_active = 'Y'
  ~' into l_p06_type_count;

  execute immediate q'~
    select count(*)
      from (
        select a.id
          from of_assets a
         where not (
           (a.status_code = 'IN_STOCK'
             and not exists (select 1 from of_asset_reservations r
                              where r.asset_id = a.id and r.status_code = 'ACTIVE')
             and not exists (select 1 from of_asset_assignments s
                              where s.asset_id = a.id and s.returned_at is null)
             and not exists (select 1 from of_asset_repairs p
                              where p.asset_id = a.id
                                and p.status_code in ('OPEN', 'IN_PROGRESS')))
           or
           (a.status_code = 'RESERVED'
             and (select count(*) from of_asset_reservations r
                   where r.asset_id = a.id and r.status_code = 'ACTIVE') = 1
             and not exists (select 1 from of_asset_assignments s
                              where s.asset_id = a.id and s.returned_at is null)
             and not exists (select 1 from of_asset_repairs p
                              where p.asset_id = a.id
                                and p.status_code in ('OPEN', 'IN_PROGRESS')))
           or
           (a.status_code = 'ASSIGNED'
             and not exists (select 1 from of_asset_reservations r
                              where r.asset_id = a.id and r.status_code = 'ACTIVE')
             and (select count(*) from of_asset_assignments s
                   where s.asset_id = a.id and s.returned_at is null) = 1
             and not exists (select 1 from of_asset_repairs p
                              where p.asset_id = a.id
                                and p.status_code in ('OPEN', 'IN_PROGRESS')))
           or
           (a.status_code = 'IN_REPAIR'
             and not exists (select 1 from of_asset_reservations r
                              where r.asset_id = a.id and r.status_code = 'ACTIVE')
             and not exists (select 1 from of_asset_assignments s
                              where s.asset_id = a.id and s.returned_at is null)
             and (select count(*) from of_asset_repairs p
                   where p.asset_id = a.id
                     and p.status_code in ('OPEN', 'IN_PROGRESS')) = 1)
           or
           (a.status_code in ('LOST', 'RETIRED')
             and not exists (select 1 from of_asset_reservations r
                              where r.asset_id = a.id and r.status_code = 'ACTIVE')
             and not exists (select 1 from of_asset_assignments s
                              where s.asset_id = a.id and s.returned_at is null)
             and not exists (select 1 from of_asset_repairs p
                              where p.asset_id = a.id
                                and p.status_code in ('OPEN', 'IN_PROGRESS')))
         )
      )
  ~' into l_p06_drift_count;

  execute immediate q'~
    select
      (select count(*) from of_assets where purchase_order_item_id is not null)
      +
      (select count(*) from of_asset_repairs where supplier_id is not null)
      from dual
  ~' into l_deferred_count;

  select count(*) into l_collision_count
    from user_objects
   where object_name in (
     'OF_CATALOG_ITEMS', 'OF_SUPPLIERS', 'OF_PURCHASE_REQUESTS',
     'OF_PURCHASE_REQUEST_ITEMS', 'OF_APPROVALS', 'OF_PURCHASE_ORDERS',
     'OF_PURCHASE_ORDER_ITEMS', 'OF_GOODS_RECEIPTS',
     'OF_GOODS_RECEIPT_ITEMS', 'OF_STOCK_MOVEMENTS',
     'OF_INVENTORY_BALANCES', 'OF_PROCUREMENT_API', 'OF_INVENTORY_API',
     'OF_STOCK_MOVEMENT_GUARD_TRG'
   )
     and object_type in ('TABLE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER');

  if l_base_count <> 10 then
    raise_application_error(
      -20340,
      'P07 stopped: expected 10 required foundation/P06 tables, found ' ||
      l_base_count || '.'
    );
  end if;

  if l_dependency_count <> 15 or l_p06_type_count <> 6 then
    raise_application_error(
      -20341,
      'P07 stopped: expected 15 valid P04-P06 code objects and 6 active ' ||
      'P06 asset types; found ' || l_dependency_count || ' and ' ||
      l_p06_type_count || '. Complete P06 tests and final validation first.'
    );
  end if;

  if l_p06_drift_count <> 0 or l_deferred_count <> 0 then
    raise_application_error(
      -20342,
      'P07 stopped: P06 has ' || l_p06_drift_count ||
      ' lifecycle mismatch(es) and ' || l_deferred_count ||
      ' unresolved deferred procurement reference(s). Reconcile P06 first.'
    );
  end if;

  if l_collision_count <> 0 then
    raise_application_error(
      -20343,
      'P07 stopped: ' || l_collision_count ||
      ' P07 object(s) already exist. Validate or use the guarded rollback; ' ||
      'do not mix installations.'
    );
  end if;

  run_ddl(q'~
    create table of_catalog_items (
      id                       number generated by default on null as identity,
      code                     varchar2(50 char)                         not null,
      name                     varchar2(200 char)                        not null,
      description              varchar2(2000 char),
      unit_of_measure_code     varchar2(20 char)        default 'EA'     not null,
      is_stocked               char(1 char)             default 'Y'      not null,
      creates_asset            char(1 char)             default 'N'      not null,
      asset_type_id            number,
      default_currency_code    char(3 char),
      is_active                char(1 char)             default 'Y'      not null,
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_catalog_items_pk primary key (id),
      constraint of_catalog_items_code_uk unique (code),
      constraint of_catalog_asset_type_fk
        foreign key (asset_type_id) references of_asset_types (id),
      constraint of_catalog_code_ck check (code = upper(trim(code))),
      constraint of_catalog_name_ck check (name = trim(name)),
      constraint of_catalog_uom_ck check (
        unit_of_measure_code = upper(trim(unit_of_measure_code))
      ),
      constraint of_catalog_flags_ck check (
        is_stocked in ('Y', 'N') and creates_asset in ('Y', 'N')
        and not (is_stocked = 'Y' and creates_asset = 'Y')
      ),
      constraint of_catalog_asset_policy_ck check (
        (creates_asset = 'Y' and asset_type_id is not null)
        or (creates_asset = 'N' and asset_type_id is null)
      ),
      constraint of_catalog_currency_ck check (
        default_currency_code is null
        or default_currency_code = upper(trim(default_currency_code))
      ),
      constraint of_catalog_active_ck check (is_active in ('Y', 'N')),
      constraint of_catalog_version_ck check (row_version > 0)
    )
  ~');

  run_ddl(q'~
    create table of_suppliers (
      id                       number generated by default on null as identity,
      supplier_code            varchar2(50 char)                         not null,
      name                     varchar2(200 char)                        not null,
      contact_name             varchar2(200 char),
      email                    varchar2(255 char),
      phone                    varchar2(50 char),
      address_text             varchar2(1000 char),
      is_active                char(1 char)             default 'Y'      not null,
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_suppliers_pk primary key (id),
      constraint of_suppliers_code_uk unique (supplier_code),
      constraint of_suppliers_code_ck
        check (supplier_code = upper(trim(supplier_code))),
      constraint of_suppliers_name_ck check (name = trim(name)),
      constraint of_suppliers_email_ck check (email is null or email = trim(email)),
      constraint of_suppliers_active_ck check (is_active in ('Y', 'N')),
      constraint of_suppliers_version_ck check (row_version > 0)
    )
  ~');

  run_ddl(q'~
    create table of_purchase_requests (
      id                       number generated by default on null as identity,
      request_no               varchar2(30 char)                         not null,
      requester_user_id        number                                    not null,
      requester_department_id  number                                    not null,
      status_code              varchar2(30 char)        default 'DRAFT'   not null,
      business_justification   clob                                      not null,
      currency_code            char(3 char)                              not null,
      total_amount             number(14,2)            default 0         not null,
      approval_threshold_snapshot number(14,2),
      submitted_at             timestamp with local time zone,
      approved_at              timestamp with local time zone,
      closed_at                timestamp with local time zone,
      cancellation_reason      varchar2(1000 char),
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_purchase_requests_pk primary key (id),
      constraint of_purchase_requests_no_uk unique (request_no),
      constraint of_pr_requester_fk
        foreign key (requester_user_id) references of_app_users (id),
      constraint of_pr_department_fk
        foreign key (requester_department_id) references of_departments (id),
      constraint of_pr_no_ck check (request_no = upper(trim(request_no))),
      constraint of_pr_status_ck check (status_code in (
        'DRAFT', 'SUBMITTED', 'MANAGER_REVIEW', 'OPERATIONS_REVIEW',
        'PROCUREMENT_REVIEW', 'APPROVED', 'PARTIALLY_ORDERED', 'ORDERED',
        'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED', 'REJECTED', 'CANCELLED'
      )),
      constraint of_pr_currency_ck check (
        currency_code = upper(trim(currency_code))
      ),
      constraint of_pr_total_ck check (total_amount >= 0),
      constraint of_pr_threshold_ck check (
        approval_threshold_snapshot is null
        or approval_threshold_snapshot >= 0
      ),
      constraint of_pr_cancel_ck check (
        status_code <> 'CANCELLED' or trim(cancellation_reason) is not null
      ),
      constraint of_pr_version_ck check (row_version > 0)
    )
  ~');

  run_ddl(q'~
    create table of_purchase_request_items (
      id                       number generated by default on null as identity,
      purchase_request_id      number                                    not null,
      line_no                  number(6)                                 not null,
      catalog_item_id          number,
      item_description         varchar2(1000 char)                        not null,
      quantity                 number(14,3)                              not null,
      estimated_unit_price     number(14,2)                              not null,
      line_total               number(14,2)                              not null,
      required_by_date         date,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_purchase_request_items_pk primary key (id),
      constraint of_pr_items_request_fk
        foreign key (purchase_request_id) references of_purchase_requests (id),
      constraint of_pr_items_catalog_fk
        foreign key (catalog_item_id) references of_catalog_items (id),
      constraint of_pr_items_line_uk unique (purchase_request_id, line_no),
      constraint of_pr_items_line_ck check (line_no > 0),
      constraint of_pr_items_quantity_ck check (quantity > 0),
      constraint of_pr_items_price_ck check (estimated_unit_price >= 0),
      constraint of_pr_items_total_ck check (
        line_total = round(quantity * estimated_unit_price, 2)
      )
    )
  ~');

  run_ddl(q'~
    create table of_approvals (
      id                       number generated by default on null as identity,
      purchase_request_id      number                                    not null,
      sequence_no              number(4)                                 not null,
      stage_code               varchar2(30 char)                          not null,
      status_code              varchar2(20 char)        default 'PENDING' not null,
      assigned_to_user_id      number                                    not null,
      requested_at             timestamp with local time zone
                                                       default systimestamp not null,
      due_at                   timestamp with local time zone,
      decided_by_user_id       number,
      decided_at               timestamp with local time zone,
      decision_comment         varchar2(2000 char),
      apex_task_id             number,
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_approvals_pk primary key (id),
      constraint of_approvals_request_fk
        foreign key (purchase_request_id) references of_purchase_requests (id),
      constraint of_approvals_assigned_fk
        foreign key (assigned_to_user_id) references of_app_users (id),
      constraint of_approvals_decided_fk
        foreign key (decided_by_user_id) references of_app_users (id),
      constraint of_approvals_sequence_uk
        unique (purchase_request_id, sequence_no),
      constraint of_approvals_stage_uk unique (purchase_request_id, stage_code),
      constraint of_approvals_sequence_ck check (sequence_no > 0),
      constraint of_approvals_stage_ck check (
        stage_code in ('MANAGER', 'OPERATIONS', 'PROCUREMENT')
      ),
      constraint of_approvals_status_ck check (
        status_code in ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')
      ),
      constraint of_approvals_decision_ck check (
        (status_code = 'PENDING' and decided_by_user_id is null
          and decided_at is null)
        or
        (status_code in ('APPROVED', 'REJECTED', 'CANCELLED')
          and decided_by_user_id is not null and decided_at is not null)
      ),
      constraint of_approvals_reject_ck check (
        status_code <> 'REJECTED' or trim(decision_comment) is not null
      ),
      constraint of_approvals_due_ck check (
        due_at is null or due_at >= requested_at
      ),
      constraint of_approvals_version_ck check (row_version > 0)
    )
  ~');

  run_ddl(q'~
    create table of_purchase_orders (
      id                       number generated by default on null as identity,
      po_no                    varchar2(30 char)                         not null,
      purchase_request_id      number                                    not null,
      supplier_id              number                                    not null,
      status_code              varchar2(30 char)        default 'DRAFT'   not null,
      order_date               date,
      expected_date            date,
      currency_code            char(3 char)                              not null,
      total_amount             number(14,2)            default 0         not null,
      issued_by_user_id        number,
      issued_at                timestamp with local time zone,
      cancellation_reason      varchar2(1000 char),
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_purchase_orders_pk primary key (id),
      constraint of_purchase_orders_no_uk unique (po_no),
      constraint of_po_request_fk
        foreign key (purchase_request_id) references of_purchase_requests (id),
      constraint of_po_supplier_fk
        foreign key (supplier_id) references of_suppliers (id),
      constraint of_po_issued_by_fk
        foreign key (issued_by_user_id) references of_app_users (id),
      constraint of_po_no_ck check (po_no = upper(trim(po_no))),
      constraint of_po_status_ck check (status_code in (
        'DRAFT', 'ISSUED', 'PARTIALLY_RECEIVED',
        'RECEIVED', 'CLOSED', 'CANCELLED'
      )),
      constraint of_po_currency_ck check (
        currency_code = upper(trim(currency_code))
      ),
      constraint of_po_total_ck check (total_amount >= 0),
      constraint of_po_date_ck check (
        expected_date is null or order_date is null or expected_date >= order_date
      ),
      constraint of_po_issue_ck check (
        (status_code = 'DRAFT' and issued_by_user_id is null and issued_at is null)
        or
        (status_code in ('ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED')
          and order_date is not null and issued_by_user_id is not null
          and issued_at is not null)
        or
        status_code = 'CANCELLED'
      ),
      constraint of_po_cancel_ck check (
        status_code <> 'CANCELLED' or trim(cancellation_reason) is not null
      ),
      constraint of_po_version_ck check (row_version > 0)
    )
  ~');

  run_ddl(q'~
    create table of_purchase_order_items (
      id                       number generated by default on null as identity,
      purchase_order_id        number                                    not null,
      line_no                  number(6)                                 not null,
      request_item_id          number,
      catalog_item_id          number                                    not null,
      item_description         varchar2(1000 char)                        not null,
      ordered_quantity         number(14,3)                              not null,
      unit_price               number(14,2)                              not null,
      line_total               number(14,2)                              not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_purchase_order_items_pk primary key (id),
      constraint of_po_items_order_fk
        foreign key (purchase_order_id) references of_purchase_orders (id),
      constraint of_po_items_request_item_fk
        foreign key (request_item_id) references of_purchase_request_items (id),
      constraint of_po_items_catalog_fk
        foreign key (catalog_item_id) references of_catalog_items (id),
      constraint of_po_items_line_uk unique (purchase_order_id, line_no),
      constraint of_po_items_request_uk
        unique (purchase_order_id, request_item_id),
      constraint of_po_items_line_ck check (line_no > 0),
      constraint of_po_items_quantity_ck check (ordered_quantity > 0),
      constraint of_po_items_price_ck check (unit_price >= 0),
      constraint of_po_items_total_ck check (
        line_total = round(ordered_quantity * unit_price, 2)
      )
    )
  ~');

  run_ddl(q'~
    create table of_goods_receipts (
      id                       number generated by default on null as identity,
      receipt_no               varchar2(30 char)                         not null,
      purchase_order_id        number                                    not null,
      status_code              varchar2(20 char)        default 'DRAFT'   not null,
      received_by_user_id      number                                    not null,
      received_at              timestamp with local time zone             not null,
      delivery_reference       varchar2(100 char),
      notes                    varchar2(2000 char),
      posted_at                timestamp with local time zone,
      idempotency_key          varchar2(200 char)                        not null,
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_goods_receipts_pk primary key (id),
      constraint of_goods_receipts_no_uk unique (receipt_no),
      constraint of_goods_receipts_key_uk unique (idempotency_key),
      constraint of_gr_order_fk
        foreign key (purchase_order_id) references of_purchase_orders (id),
      constraint of_gr_received_by_fk
        foreign key (received_by_user_id) references of_app_users (id),
      constraint of_gr_no_ck check (receipt_no = upper(trim(receipt_no))),
      constraint of_gr_status_ck check (status_code in ('DRAFT', 'POSTED', 'VOID')),
      constraint of_gr_post_ck check (
        (status_code = 'DRAFT' and posted_at is null)
        or (status_code = 'POSTED' and posted_at is not null)
        or status_code = 'VOID'
      ),
      constraint of_gr_version_ck check (row_version > 0)
    )
  ~');

  run_ddl(q'~
    create table of_goods_receipt_items (
      id                       number generated by default on null as identity,
      goods_receipt_id         number                                    not null,
      purchase_order_item_id   number                                    not null,
      quantity_received        number(14,3)                              not null,
      quantity_accepted        number(14,3)                              not null,
      quantity_rejected        number(14,3)                              not null,
      unit_cost                number(14,2)                              not null,
      location_id              number                                    not null,
      rejection_reason         varchar2(1000 char),
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_goods_receipt_items_pk primary key (id),
      constraint of_gr_items_receipt_fk
        foreign key (goods_receipt_id) references of_goods_receipts (id),
      constraint of_gr_items_po_item_fk
        foreign key (purchase_order_item_id) references of_purchase_order_items (id),
      constraint of_gr_items_location_fk
        foreign key (location_id) references of_locations (id),
      constraint of_gr_items_line_uk
        unique (goods_receipt_id, purchase_order_item_id),
      constraint of_gr_items_received_ck check (quantity_received > 0),
      constraint of_gr_items_accepted_ck check (quantity_accepted >= 0),
      constraint of_gr_items_rejected_ck check (quantity_rejected >= 0),
      constraint of_gr_items_sum_ck check (
        quantity_accepted + quantity_rejected = quantity_received
      ),
      constraint of_gr_items_cost_ck check (unit_cost >= 0),
      constraint of_gr_items_reason_ck check (
        quantity_rejected = 0 or trim(rejection_reason) is not null
      )
    )
  ~');

  run_ddl(q'~
    create table of_stock_movements (
      id                       number generated by default on null as identity,
      catalog_item_id          number                                    not null,
      location_id              number                                    not null,
      movement_type_code       varchar2(30 char)                          not null,
      quantity_delta           number(14,3)                              not null,
      receipt_item_id          number,
      related_movement_id      number,
      occurred_at              timestamp with local time zone
                                                       default systimestamp not null,
      performed_by_user_id     number                                    not null,
      reason_text              varchar2(1000 char),
      correlation_id           varchar2(64 char)                          not null,
      constraint of_stock_movements_pk primary key (id),
      constraint of_stock_catalog_fk
        foreign key (catalog_item_id) references of_catalog_items (id),
      constraint of_stock_location_fk
        foreign key (location_id) references of_locations (id),
      constraint of_stock_receipt_item_fk
        foreign key (receipt_item_id) references of_goods_receipt_items (id),
      constraint of_stock_related_fk
        foreign key (related_movement_id) references of_stock_movements (id),
      constraint of_stock_type_ck check (
        movement_type_code in ('RECEIPT', 'ISSUE', 'RETURN', 'ADJUSTMENT')
      ),
      constraint of_stock_quantity_ck check (quantity_delta <> 0),
      constraint of_stock_receipt_ck check (
        movement_type_code <> 'RECEIPT' or receipt_item_id is not null
      ),
      constraint of_stock_adjustment_ck check (
        movement_type_code <> 'ADJUSTMENT' or trim(reason_text) is not null
      ),
      constraint of_stock_related_self_ck check (
        related_movement_id is null or related_movement_id <> id
      )
    )
  ~');

  run_ddl(q'~
    create table of_inventory_balances (
      id                       number generated by default on null as identity,
      catalog_item_id          number                                    not null,
      location_id              number                                    not null,
      quantity_on_hand         number(14,3)            default 0         not null,
      row_version              number                  default 1         not null,
      created_at               timestamp with local time zone
                                                       default systimestamp not null,
      created_by               varchar2(255 char)       default 'SYSTEM'  not null,
      updated_at               timestamp with local time zone
                                                       default systimestamp not null,
      updated_by               varchar2(255 char)       default 'SYSTEM'  not null,
      constraint of_inventory_balances_pk primary key (id),
      constraint of_inventory_balance_uk unique (catalog_item_id, location_id),
      constraint of_inventory_catalog_fk
        foreign key (catalog_item_id) references of_catalog_items (id),
      constraint of_inventory_location_fk
        foreign key (location_id) references of_locations (id),
      constraint of_inventory_quantity_ck check (quantity_on_hand >= 0),
      constraint of_inventory_version_ck check (row_version > 0)
    )
  ~');

  run_ddl('create index of_catalog_asset_type_ix on of_catalog_items (asset_type_id)');
  run_ddl('create index of_pr_requester_ix on of_purchase_requests (requester_user_id, status_code)');
  run_ddl('create index of_pr_department_ix on of_purchase_requests (requester_department_id, status_code)');
  run_ddl('create index of_pr_items_request_ix on of_purchase_request_items (purchase_request_id)');
  run_ddl('create index of_pr_items_catalog_ix on of_purchase_request_items (catalog_item_id)');
  run_ddl('create index of_approvals_assignee_ix on of_approvals (assigned_to_user_id, status_code)');
  run_ddl(q'~create unique index of_approval_pending_uix on of_approvals (
    case when status_code = 'PENDING' then purchase_request_id end
  )~');
  run_ddl('create index of_po_request_ix on of_purchase_orders (purchase_request_id, status_code)');
  run_ddl('create index of_po_supplier_ix on of_purchase_orders (supplier_id)');
  run_ddl('create index of_po_items_order_ix on of_purchase_order_items (purchase_order_id)');
  run_ddl('create index of_po_items_request_ix on of_purchase_order_items (request_item_id)');
  run_ddl('create index of_gr_order_ix on of_goods_receipts (purchase_order_id, status_code)');
  run_ddl('create index of_gr_items_receipt_ix on of_goods_receipt_items (goods_receipt_id)');
  run_ddl('create index of_gr_items_po_item_ix on of_goods_receipt_items (purchase_order_item_id)');
  run_ddl('create index of_stock_item_location_ix on of_stock_movements (catalog_item_id, location_id, occurred_at)');
  run_ddl(q'~create unique index of_stock_receipt_uix on of_stock_movements (
    case when movement_type_code = 'RECEIPT' then receipt_item_id end
  )~');
  run_ddl(q'~create unique index of_stock_reversal_uix on of_stock_movements (
    case when related_movement_id is not null then related_movement_id end
  )~');

  run_ddl(q'~alter table of_assets add constraint of_assets_po_item_fk
    foreign key (purchase_order_item_id) references of_purchase_order_items (id)~');
  run_ddl(q'~alter table of_asset_repairs add constraint of_asset_rep_supplier_fk
    foreign key (supplier_id) references of_suppliers (id)~');

  -- ALTER TABLE can invalidate dependent PL/SQL. Recompile the P06 body now so
  -- the P07 gate finishes with its predecessor valid, not merely present.
  run_ddl('alter package of_asset_api compile body');
  select count(*) into l_dependency_count
    from user_objects
   where object_name = 'OF_ASSET_API'
     and object_type in ('PACKAGE', 'PACKAGE BODY')
     and status = 'VALID';
  if l_dependency_count <> 2 then
    raise_application_error(
      -20341,
      'P07 stopped: OF_ASSET_API did not remain valid after deferred keys.'
    );
  end if;

  run_ddl(q'~comment on table of_catalog_items is
    'Purchasable/stockable definitions and optional asset-creation policy.'~');
  run_ddl(q'~comment on table of_suppliers is
    'Active supplier directory with operational contact snapshots.'~');
  run_ddl(q'~comment on table of_purchase_requests is
    'Current employee request state with server-calculated total and routing snapshot.'~');
  run_ddl(q'~comment on table of_approvals is
    'Durable manager, operations, and procurement decisions.'~');
  run_ddl(q'~comment on table of_stock_movements is
    'Immutable signed inventory ledger; corrections use related reversing rows.'~');
  run_ddl(q'~comment on table of_inventory_balances is
    'Current on-hand quantity reconciled to the immutable movement ledger.'~');

  dbms_output.put_line('P07 prerequisite check and 11-table schema creation passed.');
end;
/

--------------------------------------------------------------------------------
-- 01. Seed non-secret settings, six catalog items, and three suppliers
--------------------------------------------------------------------------------

declare
  l_setting_count  number;
  l_catalog_count  number;
  l_supplier_count number;
begin
  merge into of_app_settings t
  using (
    select 'PURCHASE_REQUEST_PREFIX' setting_code, 'TEXT' data_type_code,
           'PR' setting_value, 'Purchase-request business number prefix.' description
      from dual
    union all select 'PURCHASE_ORDER_PREFIX', 'TEXT', 'PO',
           'Purchase-order business number prefix.' from dual
    union all select 'GOODS_RECEIPT_PREFIX', 'TEXT', 'GR',
           'Goods-receipt business number prefix.' from dual
    union all select 'PROCUREMENT_APPROVAL_THRESHOLD', 'NUMBER', '50000',
           'Amount above which operations approval is required.' from dual
    union all select 'APPROVAL_DUE_DAYS', 'NUMBER', '3',
           'Default calendar days allowed for a procurement approval.' from dual
  ) s
  on (t.setting_code = s.setting_code)
  when matched then update set
    t.data_type_code = s.data_type_code,
    t.setting_value = s.setting_value,
    t.description = s.description,
    t.is_sensitive = 'N',
    t.updated_at = systimestamp,
    t.updated_by = 'P07_SEED'
  when not matched then insert (
    setting_code, data_type_code, setting_value, description,
    is_sensitive, created_by, updated_by
  ) values (
    s.setting_code, s.data_type_code, s.setting_value, s.description,
    'N', 'P07_SEED', 'P07_SEED'
  );

  merge into of_catalog_items t
  using (
    select x.code, x.name, x.description, x.uom, x.is_stocked,
           x.creates_asset, at.id asset_type_id, 'EGP' currency_code
      from (
        select 'OFFICE_PAPER_A4' code, 'A4 Office Paper' name,
               'One ream of general-purpose A4 paper.' description,
               'REAM' uom, 'Y' is_stocked, 'N' creates_asset,
               cast(null as varchar2(30)) asset_type_code from dual
        union all select 'BLACK_TONER', 'Black Toner Cartridge',
               'Standard black toner cartridge.', 'EA', 'Y', 'N', null from dual
        union all select 'USB_C_DOCK', 'USB-C Dock',
               'Standard non-serialized desk docking unit.', 'EA', 'Y', 'N', null from dual
        union all select 'SAFETY_KIT', 'Workplace Safety Kit',
               'Boxed workplace first-response supplies.', 'BOX', 'Y', 'N', null from dual
        union all select 'STANDARD_LAPTOP', 'Standard Business Laptop',
               'Serialized laptop registered as an asset after receiving.',
               'EA', 'N', 'Y', 'LAPTOP' from dual
        union all select 'OFFICE_CHAIR', 'Ergonomic Office Chair',
               'Individually tracked ergonomic office chair.',
               'EA', 'N', 'Y', 'FURNITURE' from dual
      ) x
      left join of_asset_types at on at.code = x.asset_type_code
  ) s
  on (t.code = s.code)
  when matched then update set
    t.name = s.name,
    t.description = s.description,
    t.unit_of_measure_code = s.uom,
    t.is_stocked = s.is_stocked,
    t.creates_asset = s.creates_asset,
    t.asset_type_id = s.asset_type_id,
    t.default_currency_code = s.currency_code,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P07_SEED'
  when not matched then insert (
    code, name, description, unit_of_measure_code, is_stocked,
    creates_asset, asset_type_id, default_currency_code,
    is_active, created_by, updated_by
  ) values (
    s.code, s.name, s.description, s.uom, s.is_stocked,
    s.creates_asset, s.asset_type_id, s.currency_code,
    'Y', 'P07_SEED', 'P07_SEED'
  );

  merge into of_suppliers t
  using (
    select 'NILE_TECH' supplier_code, 'Nile Technology Supplies' name,
           'Mona Salem' contact_name, 'sales@nile-tech.example.invalid' email,
           '+20-000-000-1001' phone,
           'Synthetic Cairo technology supplier.' address_text from dual
    union all select 'DELTA_OFFICE', 'Delta Office Products',
           'Karim Adel', 'orders@delta-office.example.invalid',
           '+20-000-000-1002', 'Synthetic Alexandria office supplier.' from dual
    union all select 'CAIRO_SUPPLY', 'Cairo General Supply',
           'Sara Amin', 'procurement@cairo-supply.example.invalid',
           '+20-000-000-1003', 'Synthetic general supplier.' from dual
  ) s
  on (t.supplier_code = s.supplier_code)
  when matched then update set
    t.name = s.name,
    t.contact_name = s.contact_name,
    t.email = s.email,
    t.phone = s.phone,
    t.address_text = s.address_text,
    t.is_active = 'Y',
    t.updated_at = systimestamp,
    t.updated_by = 'P07_SEED'
  when not matched then insert (
    supplier_code, name, contact_name, email, phone, address_text,
    is_active, created_by, updated_by
  ) values (
    s.supplier_code, s.name, s.contact_name, s.email, s.phone, s.address_text,
    'Y', 'P07_SEED', 'P07_SEED'
  );

  select count(*) into l_setting_count
    from of_app_settings
   where setting_code in (
     'PURCHASE_REQUEST_PREFIX', 'PURCHASE_ORDER_PREFIX',
     'GOODS_RECEIPT_PREFIX', 'PROCUREMENT_APPROVAL_THRESHOLD',
     'APPROVAL_DUE_DAYS'
   );

  select count(*) into l_catalog_count
    from of_catalog_items
   where code in (
     'OFFICE_PAPER_A4', 'BLACK_TONER', 'USB_C_DOCK',
     'SAFETY_KIT', 'STANDARD_LAPTOP', 'OFFICE_CHAIR'
   ) and is_active = 'Y';

  select count(*) into l_supplier_count
    from of_suppliers
   where supplier_code in ('NILE_TECH', 'DELTA_OFFICE', 'CAIRO_SUPPLY')
     and is_active = 'Y';

  if l_setting_count <> 5 or l_catalog_count <> 6 or l_supplier_count <> 3 then
    rollback;
    raise_application_error(
      -20343,
      'P07 seed stopped: expected settings/catalog/suppliers 5/6/3; found ' ||
      l_setting_count || '/' || l_catalog_count || '/' || l_supplier_count || '.'
    );
  end if;

  commit;
  dbms_output.put_line('P07 reference seed committed: 5 settings, 6 items, 3 suppliers.');
end;
/

--------------------------------------------------------------------------------
-- 02. Public procurement transaction contract (15 actions)
--------------------------------------------------------------------------------

create or replace package of_procurement_api authid definer as
  procedure create_request_draft(
    p_business_justification in  clob,
    p_currency_code          in  varchar2 default 'EGP',
    p_requester_user_id      in  number default null,
    p_request_id             out number,
    p_request_no             out varchar2,
    p_row_version            out number
  );

  procedure add_request_item(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_catalog_item_id        in  number default null,
    p_item_description       in  varchar2,
    p_quantity               in  number,
    p_estimated_unit_price   in  number,
    p_required_by_date       in  date default null,
    p_request_item_id        out number,
    p_new_row_version        out number
  );

  procedure remove_request_item(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_request_item_id        in  number,
    p_new_row_version        out number
  );

  procedure submit_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_admin_reason           in  varchar2 default null,
    p_new_row_version        out number
  );

  procedure approve_manager(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2 default null,
    p_new_row_version        out number
  );

  procedure approve_operations(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2 default null,
    p_new_row_version        out number
  );

  procedure approve_procurement(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2 default null,
    p_new_row_version        out number
  );

  procedure reject_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2,
    p_new_row_version        out number
  );

  procedure cancel_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_reason_text            in  varchar2,
    p_new_row_version        out number
  );

  procedure create_order_draft(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_supplier_id            in  number,
    p_po_id                   out number,
    p_po_no                   out varchar2,
    p_po_row_version          out number,
    p_request_row_version     out number
  );

  procedure add_order_item(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_request_item_id        in  number,
    p_ordered_quantity       in  number,
    p_unit_price             in  number,
    p_po_item_id             out number,
    p_new_po_version         out number
  );

  procedure issue_order(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_order_date             in  date,
    p_expected_date          in  date default null,
    p_new_po_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  );

  procedure cancel_order(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_reason_text            in  varchar2,
    p_new_po_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  );

  procedure close_order(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_new_po_version         out number
  );

  procedure close_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_new_row_version        out number
  );
end of_procurement_api;
/

--------------------------------------------------------------------------------
-- 03. Procurement implementation
--------------------------------------------------------------------------------

create or replace package body of_procurement_api as
  procedure fail(p_code in number, p_message in varchar2) is
  begin
    raise_application_error(p_code, p_message);
  end fail;

  procedure assert_text(
    p_value in varchar2, p_label in varchar2, p_max_length in number
  ) is
  begin
    if trim(p_value) is null then
      fail(-20300, p_label || ' is required.');
    end if;
    if length(trim(p_value)) > p_max_length then
      fail(-20300, p_label || ' exceeds ' || p_max_length || ' characters.');
    end if;
  end assert_text;

  procedure assert_clob_text(p_value in clob, p_label in varchar2) is
    l_probe varchar2(4000 char);
  begin
    if p_value is null then
      fail(-20300, p_label || ' is required.');
    end if;
    l_probe := dbms_lob.substr(p_value, 4000, 1);
    if trim(l_probe) is null then
      fail(-20300, p_label || ' must contain nonblank text.');
    end if;
  end assert_clob_text;

  function actor_id return number is
  begin
    of_security_api.assert_authenticated;
    return of_security_api.current_user_id();
  end actor_id;

  function actor_name return varchar2 is
  begin
    return of_security_api.current_username();
  end actor_name;

  procedure assert_procurement is
  begin
    of_security_api.assert_authenticated;
    if not of_security_api.is_procurement_officer()
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'A procurement officer or operations administrator is required.');
    end if;
  end assert_procurement;

  function currency_code(p_value in varchar2) return varchar2 is
    l_value varchar2(3 char);
  begin
    l_value := of_util_api.normalize_code(p_value);
    if l_value is null or not regexp_like(l_value, '^[A-Z]{3}$') then
      fail(-20300, 'A three-letter uppercase currency code is required.');
    end if;
    return l_value;
  end currency_code;

  function business_number(
    p_setting_code in varchar2,
    p_default       in varchar2
  ) return varchar2 is
    l_prefix varchar2(8 char);
  begin
    l_prefix := substr(
      of_util_api.normalize_code(
        of_util_api.get_setting_text(p_setting_code, p_default)
      ),
      1,
      8
    );
    if l_prefix is null or not regexp_like(l_prefix, '^[A-Z][A-Z0-9_]{0,7}$') then
      fail(-20300, 'Invalid business-number prefix setting ' || p_setting_code || '.');
    end if;
    return l_prefix || '-' || to_char(systimestamp, 'YYMMDDHH24MISSFF3') ||
           '-' || substr(of_util_api.new_correlation_id(), 1, 4);
  end business_number;

  function state_json(
    p_status in varchar2,
    p_version in number,
    p_total in number
  ) return clob is
    l_json json_object_t := json_object_t();
  begin
    if p_status is null then l_json.put_null('statusCode');
    else l_json.put('statusCode', p_status); end if;
    if p_version is null then l_json.put_null('rowVersion');
    else l_json.put('rowVersion', p_version); end if;
    if p_total is null then l_json.put_null('totalAmount');
    else l_json.put('totalAmount', p_total); end if;
    return l_json.to_clob();
  end state_json;

  procedure audit_event(
    p_action_code in varchar2,
    p_entity_type in varchar2,
    p_entity_id in number,
    p_entity_key in varchar2,
    p_old_status in varchar2,
    p_new_status in varchar2,
    p_old_version in number,
    p_new_version in number,
    p_old_total in number,
    p_new_total in number
  ) is
    l_id varchar2(64 char);
  begin
    l_id := of_audit_api.record_event(
      p_action_code      => p_action_code,
      p_entity_type_code => p_entity_type,
      p_entity_id        => p_entity_id,
      p_entity_key       => p_entity_key,
      p_old_values_json  => state_json(p_old_status, p_old_version, p_old_total),
      p_new_values_json  => state_json(p_new_status, p_new_version, p_new_total)
    );
  end audit_event;

  procedure lock_request(
    p_request_id           in  number,
    p_expected_row_version in  number,
    p_request              out of_purchase_requests%rowtype
  ) is
    e_busy exception;
    pragma exception_init(e_busy, -54);
  begin
    if p_request_id is null or p_expected_row_version is null
       or p_expected_row_version < 1 then
      fail(-20300, 'Request ID and expected row version are required.');
    end if;
    select * into p_request
      from of_purchase_requests
     where id = p_request_id
       for update nowait;
    if p_request.row_version <> p_expected_row_version then
      fail(-20302, 'Purchase request changed. Refresh and try again.');
    end if;
  exception
    when no_data_found then
      fail(-20301, 'Purchase request does not exist or is unavailable.');
    when e_busy then
      fail(-20303, 'Purchase request is being changed by another session.');
  end lock_request;

  procedure lock_order(
    p_po_id               in  number,
    p_expected_po_version in  number,
    p_request             out of_purchase_requests%rowtype,
    p_order               out of_purchase_orders%rowtype
  ) is
    l_request_id number;
    e_busy exception;
    pragma exception_init(e_busy, -54);
  begin
    if p_po_id is null or p_expected_po_version is null
       or p_expected_po_version < 1 then
      fail(-20300, 'Purchase order ID and expected row version are required.');
    end if;

    select purchase_request_id into l_request_id
      from of_purchase_orders
     where id = p_po_id;

    select * into p_request
      from of_purchase_requests
     where id = l_request_id
       for update nowait;

    select * into p_order
      from of_purchase_orders
     where id = p_po_id
       for update nowait;

    if p_order.row_version <> p_expected_po_version then
      fail(-20302, 'Purchase order changed. Refresh and try again.');
    end if;
  exception
    when no_data_found then
      fail(-20301, 'Purchase order does not exist or is unavailable.');
    when e_busy then
      fail(-20303, 'Purchase request/order is being changed by another session.');
  end lock_order;

  function request_total(p_request_id in number) return number is
    l_total number;
  begin
    select coalesce(sum(line_total), 0) into l_total
      from of_purchase_request_items
     where purchase_request_id = p_request_id;
    return round(l_total, 2);
  end request_total;

  function order_total(p_po_id in number) return number is
    l_total number;
  begin
    select coalesce(sum(line_total), 0) into l_total
      from of_purchase_order_items
     where purchase_order_id = p_po_id;
    return round(l_total, 2);
  end order_total;

  procedure assert_request_owner_or_admin(
    p_request in of_purchase_requests%rowtype
  ) is
  begin
    if actor_id() <> p_request.requester_user_id
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'Only the requester or an operations administrator may edit this draft.');
    end if;
  end assert_request_owner_or_admin;

  function select_approver(
    p_role_code          in varchar2,
    p_department_id      in number,
    p_requester_user_id  in number
  ) return number is
    l_actor_id number;
    l_user_id  number;
  begin
    l_actor_id := actor_id();
    begin
      select id into l_user_id
        from (
          select u.id
            from of_app_users u
            join of_user_roles ur
              on ur.user_id = u.id and ur.is_active = 'Y'
            join of_roles r
              on r.id = ur.role_id and r.is_active = 'Y'
           where u.is_active = 'Y'
             and r.code = p_role_code
             and u.id <> p_requester_user_id
             and (p_department_id is null or u.department_id = p_department_id)
           order by case when u.id = l_actor_id then 0 else 1 end, u.id
        )
       where rownum = 1;
    exception
      when no_data_found then
        fail(-20308, 'No eligible ' || p_role_code || ' approver is available.');
    end;
    return l_user_id;
  end select_approver;

  procedure create_pending_approval(
    p_request_id   in number,
    p_sequence_no  in number,
    p_stage_code   in varchar2,
    p_assignee_id  in number
  ) is
    l_due_days  number;
    l_actor_name varchar2(255 char);
  begin
    l_due_days := greatest(
      0,
      of_util_api.get_setting_number('APPROVAL_DUE_DAYS', 3)
    );
    l_actor_name := actor_name();
    insert into of_approvals (
      purchase_request_id, sequence_no, stage_code, status_code,
      assigned_to_user_id, requested_at, due_at,
      created_by, updated_by
    ) values (
      p_request_id, p_sequence_no, p_stage_code, 'PENDING',
      p_assignee_id, systimestamp,
      systimestamp + numtodsinterval(l_due_days, 'DAY'),
      l_actor_name, l_actor_name
    );
  end create_pending_approval;

  procedure assert_pending_approval(
    p_request       in  of_purchase_requests%rowtype,
    p_stage_code    in  varchar2,
    p_approval_id   out number
  ) is
    l_assignee number;
    l_actor    number;
  begin
    select id, assigned_to_user_id
      into p_approval_id, l_assignee
      from of_approvals
     where purchase_request_id = p_request.id
       and stage_code = p_stage_code
       and status_code = 'PENDING'
       for update;

    l_actor := actor_id();
    if l_actor = p_request.requester_user_id then
      fail(-20305, 'A requester cannot approve or reject their own request.');
    end if;
    if l_actor <> l_assignee and not of_security_api.is_operations_admin() then
      fail(-20305, 'The pending approval is assigned to another user.');
    end if;

    if p_stage_code = 'MANAGER'
       and not of_security_api.is_manager()
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'A manager role is required for manager review.');
    elsif p_stage_code = 'OPERATIONS'
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'An operations administrator is required for operations review.');
    elsif p_stage_code = 'PROCUREMENT'
       and not of_security_api.is_procurement_officer()
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'A procurement role is required for procurement review.');
    end if;
  exception
    when no_data_found then
      fail(-20308, 'The required pending approval is missing.');
  end assert_pending_approval;

  procedure complete_approval(
    p_approval_id in number,
    p_status_code in varchar2,
    p_comment     in varchar2
  ) is
    l_actor_id   number;
    l_actor_name varchar2(255 char);
  begin
    l_actor_id := actor_id();
    l_actor_name := actor_name();
    update of_approvals
       set status_code = p_status_code,
           decided_by_user_id = l_actor_id,
           decided_at = systimestamp,
           decision_comment = substr(trim(p_comment), 1, 2000),
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = l_actor_name
     where id = p_approval_id;
  end complete_approval;

  function ordering_status(p_request_id in number) return varchar2 is
    l_issued_quantity number;
    l_incomplete      number;
  begin
    select coalesce(sum(oi.ordered_quantity), 0)
      into l_issued_quantity
      from of_purchase_orders o
      join of_purchase_order_items oi on oi.purchase_order_id = o.id
     where o.purchase_request_id = p_request_id
       and o.status_code in (
         'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
       );

    if l_issued_quantity = 0 then
      return 'APPROVED';
    end if;

    select count(*) into l_incomplete
      from of_purchase_request_items ri
     where ri.purchase_request_id = p_request_id
       and coalesce(
         (
           select sum(oi.ordered_quantity)
             from of_purchase_order_items oi
             join of_purchase_orders o on o.id = oi.purchase_order_id
            where oi.request_item_id = ri.id
              and o.status_code in (
                'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
              )
         ),
         0
       ) < ri.quantity;

    if l_incomplete = 0 then return 'ORDERED';
    else return 'PARTIALLY_ORDERED'; end if;
  end ordering_status;

  procedure create_request_draft(
    p_business_justification in  clob,
    p_currency_code          in  varchar2 default 'EGP',
    p_requester_user_id      in  number default null,
    p_request_id             out number,
    p_request_no             out varchar2,
    p_row_version            out number
  ) is
    l_actor_id      number;
    l_actor_name    varchar2(255 char);
    l_requester_id  number;
    l_department_id number;
    l_currency      varchar2(3 char);
  begin
    savepoint of_procurement_api_action;
    p_request_id := null; p_request_no := null; p_row_version := null;
    assert_clob_text(p_business_justification, 'Business justification');
    l_actor_id := actor_id();
    l_actor_name := actor_name();
    l_requester_id := coalesce(p_requester_user_id, l_actor_id);
    if l_requester_id <> l_actor_id and not of_security_api.is_operations_admin() then
      fail(-20305, 'Only an operations administrator may create for another user.');
    end if;
    if l_requester_id = l_actor_id
       and not of_security_api.is_employee()
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'An employee role is required to create a purchase request.');
    end if;

    begin
      select department_id into l_department_id
        from of_app_users
       where id = l_requester_id and is_active = 'Y';
    exception when no_data_found then
      fail(-20306, 'Requester is missing or inactive.');
    end;

    l_currency := currency_code(p_currency_code);
    p_request_no := business_number('PURCHASE_REQUEST_PREFIX', 'PR');
    insert into of_purchase_requests (
      request_no, requester_user_id, requester_department_id, status_code,
      business_justification, currency_code, total_amount, row_version,
      created_by, updated_by
    ) values (
      p_request_no, l_requester_id, l_department_id, 'DRAFT',
      p_business_justification, l_currency, 0, 1,
      l_actor_name, l_actor_name
    ) returning id, row_version into p_request_id, p_row_version;

    audit_event(
      'PURCHASE_REQUEST_CREATED', 'PURCHASE_REQUEST',
      p_request_id, p_request_no, null, 'DRAFT', null, p_row_version, null, 0
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end create_request_draft;

  procedure add_request_item(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_catalog_item_id        in  number default null,
    p_item_description       in  varchar2,
    p_quantity               in  number,
    p_estimated_unit_price   in  number,
    p_required_by_date       in  date default null,
    p_request_item_id        out number,
    p_new_row_version        out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_actor_name varchar2(255 char);
    l_line_no    number;
    l_total      number;
    l_count      number;
  begin
    savepoint of_procurement_api_action;
    p_request_item_id := null; p_new_row_version := null;
    lock_request(p_request_id, p_expected_row_version, l_request);
    assert_request_owner_or_admin(l_request);
    if l_request.status_code <> 'DRAFT' then
      fail(-20304, 'Request items can be added only while the request is DRAFT.');
    end if;
    assert_text(p_item_description, 'Item description', 1000);
    if p_quantity is null or p_quantity <= 0
       or p_estimated_unit_price is null or p_estimated_unit_price < 0 then
      fail(-20300, 'Quantity must be positive and estimated price nonnegative.');
    end if;
    if p_quantity <> round(p_quantity, 3)
       or p_estimated_unit_price <> round(p_estimated_unit_price, 2) then
      fail(-20300, 'Quantity supports 3 decimals and estimated price supports 2.');
    end if;
    if p_catalog_item_id is not null then
      select count(*) into l_count from of_catalog_items
       where id = p_catalog_item_id and is_active = 'Y';
      if l_count <> 1 then fail(-20306, 'Catalog item is missing or inactive.'); end if;
    end if;

    select coalesce(max(line_no), 0) + 1 into l_line_no
      from of_purchase_request_items
     where purchase_request_id = l_request.id;
    l_actor_name := actor_name();
    insert into of_purchase_request_items (
      purchase_request_id, line_no, catalog_item_id, item_description,
      quantity, estimated_unit_price, line_total, required_by_date,
      created_by, updated_by
    ) values (
      l_request.id, l_line_no, p_catalog_item_id, trim(p_item_description),
      p_quantity, p_estimated_unit_price,
      round(p_quantity * p_estimated_unit_price, 2), p_required_by_date,
      l_actor_name, l_actor_name
    ) returning id into p_request_item_id;

    l_total := request_total(l_request.id);
    update of_purchase_requests
       set total_amount = l_total, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_REQUEST_ITEM_ADDED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, 'DRAFT', 'DRAFT',
      l_request.row_version, p_new_row_version, l_request.total_amount, l_total
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end add_request_item;

  procedure remove_request_item(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_request_item_id        in  number,
    p_new_row_version        out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_actor_name varchar2(255 char);
    l_total      number;
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    lock_request(p_request_id, p_expected_row_version, l_request);
    assert_request_owner_or_admin(l_request);
    if l_request.status_code <> 'DRAFT' then
      fail(-20304, 'Request items can be removed only while the request is DRAFT.');
    end if;
    delete from of_purchase_request_items
     where id = p_request_item_id and purchase_request_id = l_request.id;
    if sql%rowcount <> 1 then fail(-20301, 'Request item does not exist.'); end if;
    l_actor_name := actor_name();
    l_total := request_total(l_request.id);
    update of_purchase_requests
       set total_amount = l_total, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_REQUEST_ITEM_REMOVED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, 'DRAFT', 'DRAFT',
      l_request.row_version, p_new_row_version, l_request.total_amount, l_total
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end remove_request_item;

  procedure submit_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_admin_reason           in  varchar2 default null,
    p_new_row_version        out number
  ) is
    l_request       of_purchase_requests%rowtype;
    l_actor_id      number;
    l_actor_name    varchar2(255 char);
    l_department_id number;
    l_manager_id    number;
    l_item_count    number;
    l_total         number;
    l_threshold     number;
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code <> 'DRAFT' then
      fail(-20304, 'Only a DRAFT request may be submitted.');
    end if;
    l_actor_id := actor_id();
    if l_actor_id <> l_request.requester_user_id then
      if not of_security_api.is_operations_admin() then
        fail(-20305, 'Only the requester may submit this request.');
      end if;
      assert_text(p_admin_reason, 'Administrative submission reason', 1000);
    end if;

    select count(*) into l_item_count
      from of_purchase_request_items
     where purchase_request_id = l_request.id;
    if l_item_count = 0 then fail(-20307, 'At least one request item is required.'); end if;
    l_total := request_total(l_request.id);
    if l_total <= 0 then fail(-20307, 'Request total must be positive.'); end if;
    select department_id into l_department_id
      from of_app_users
     where id = l_request.requester_user_id and is_active = 'Y';
    l_threshold := greatest(
      0,
      of_util_api.get_setting_number('PROCUREMENT_APPROVAL_THRESHOLD', 50000)
    );
    l_manager_id := select_approver(
      'MANAGER', l_department_id, l_request.requester_user_id
    );
    create_pending_approval(l_request.id, 1, 'MANAGER', l_manager_id);
    l_actor_name := actor_name();
    update of_purchase_requests
       set requester_department_id = l_department_id,
           status_code = 'MANAGER_REVIEW', total_amount = l_total,
           approval_threshold_snapshot = l_threshold,
           submitted_at = systimestamp, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      case when l_actor_id = l_request.requester_user_id
           then 'PURCHASE_REQUEST_SUBMITTED'
           else 'PURCHASE_REQUEST_SUBMITTED_ADMIN' end,
      'PURCHASE_REQUEST', l_request.id, l_request.request_no,
      'DRAFT', 'MANAGER_REVIEW', l_request.row_version, p_new_row_version,
      l_request.total_amount, l_total
    );
  exception when no_data_found then
    rollback to of_procurement_api_action;
    fail(-20306, 'Requester is missing or inactive.');
  when others then
    rollback to of_procurement_api_action; raise;
  end submit_request;

  procedure approve_manager(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2 default null,
    p_new_row_version        out number
  ) is
    l_request     of_purchase_requests%rowtype;
    l_approval_id number;
    l_assignee    number;
    l_new_status  varchar2(30 char);
    l_sequence    number;
    l_actor_name  varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code <> 'MANAGER_REVIEW' then
      fail(-20304, 'Manager approval requires MANAGER_REVIEW status.');
    end if;
    assert_pending_approval(l_request, 'MANAGER', l_approval_id);
    complete_approval(l_approval_id, 'APPROVED', p_decision_comment);
    if l_request.total_amount > l_request.approval_threshold_snapshot then
      l_new_status := 'OPERATIONS_REVIEW';
      l_sequence := 2;
      l_assignee := select_approver(
        'OPERATIONS_ADMIN', null, l_request.requester_user_id
      );
      create_pending_approval(l_request.id, l_sequence, 'OPERATIONS', l_assignee);
    else
      l_new_status := 'PROCUREMENT_REVIEW';
      l_sequence := 2;
      l_assignee := select_approver(
        'PROCUREMENT_OFFICER', null, l_request.requester_user_id
      );
      create_pending_approval(l_request.id, l_sequence, 'PROCUREMENT', l_assignee);
    end if;
    l_actor_name := actor_name();
    update of_purchase_requests
       set status_code = l_new_status, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_MANAGER_APPROVED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, 'MANAGER_REVIEW', l_new_status,
      l_request.row_version, p_new_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end approve_manager;

  procedure approve_operations(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2 default null,
    p_new_row_version        out number
  ) is
    l_request     of_purchase_requests%rowtype;
    l_approval_id number;
    l_assignee    number;
    l_actor_name  varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code <> 'OPERATIONS_REVIEW' then
      fail(-20304, 'Operations approval requires OPERATIONS_REVIEW status.');
    end if;
    assert_pending_approval(l_request, 'OPERATIONS', l_approval_id);
    complete_approval(l_approval_id, 'APPROVED', p_decision_comment);
    l_assignee := select_approver(
      'PROCUREMENT_OFFICER', null, l_request.requester_user_id
    );
    create_pending_approval(l_request.id, 3, 'PROCUREMENT', l_assignee);
    l_actor_name := actor_name();
    update of_purchase_requests
       set status_code = 'PROCUREMENT_REVIEW', row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_OPERATIONS_APPROVED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no,
      'OPERATIONS_REVIEW', 'PROCUREMENT_REVIEW',
      l_request.row_version, p_new_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end approve_operations;

  procedure approve_procurement(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2 default null,
    p_new_row_version        out number
  ) is
    l_request     of_purchase_requests%rowtype;
    l_approval_id number;
    l_actor_name  varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code <> 'PROCUREMENT_REVIEW' then
      fail(-20304, 'Procurement approval requires PROCUREMENT_REVIEW status.');
    end if;
    assert_pending_approval(l_request, 'PROCUREMENT', l_approval_id);
    complete_approval(l_approval_id, 'APPROVED', p_decision_comment);
    l_actor_name := actor_name();
    update of_purchase_requests
       set status_code = 'APPROVED', approved_at = systimestamp,
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_PROCUREMENT_APPROVED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no,
      'PROCUREMENT_REVIEW', 'APPROVED',
      l_request.row_version, p_new_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end approve_procurement;

  procedure reject_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_decision_comment       in  varchar2,
    p_new_row_version        out number
  ) is
    l_request     of_purchase_requests%rowtype;
    l_stage       varchar2(30 char);
    l_approval_id number;
    l_actor_name  varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    assert_text(p_decision_comment, 'Rejection comment', 2000);
    lock_request(p_request_id, p_expected_row_version, l_request);
    l_stage := case l_request.status_code
      when 'MANAGER_REVIEW' then 'MANAGER'
      when 'OPERATIONS_REVIEW' then 'OPERATIONS'
      when 'PROCUREMENT_REVIEW' then 'PROCUREMENT'
      else null
    end;
    if l_stage is null then
      fail(-20304, 'Only a request in an active review stage may be rejected.');
    end if;
    assert_pending_approval(l_request, l_stage, l_approval_id);
    complete_approval(l_approval_id, 'REJECTED', p_decision_comment);
    l_actor_name := actor_name();
    update of_purchase_requests
       set status_code = 'REJECTED', closed_at = systimestamp,
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_REQUEST_REJECTED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, l_request.status_code, 'REJECTED',
      l_request.row_version, p_new_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end reject_request;

  procedure cancel_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_reason_text            in  varchar2,
    p_new_row_version        out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_actor_id   number;
    l_actor_name varchar2(255 char);
    l_posted     number;
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    assert_text(p_reason_text, 'Cancellation reason', 1000);
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code in ('CLOSED', 'REJECTED', 'CANCELLED') then
      fail(-20304, 'This request is already terminal.');
    end if;
    l_actor_id := actor_id();
    if l_request.status_code = 'DRAFT' then
      if l_actor_id <> l_request.requester_user_id
         and not of_security_api.is_operations_admin() then
        fail(-20305, 'Only the requester or operations admin may cancel a draft.');
      end if;
    elsif not of_security_api.is_operations_admin() then
      fail(-20305, 'Only an operations administrator may cancel after submission.');
    end if;

    select count(*) into l_posted
      from of_goods_receipts r
      join of_purchase_orders o on o.id = r.purchase_order_id
     where o.purchase_request_id = l_request.id
       and r.status_code = 'POSTED';
    if l_posted > 0 then
      fail(-20304, 'A request with posted receipts cannot be cancelled.');
    end if;
    l_actor_name := actor_name();
    update of_approvals
       set status_code = 'CANCELLED', decided_by_user_id = l_actor_id,
           decided_at = systimestamp,
           decision_comment = substr(trim(p_reason_text), 1, 2000),
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where purchase_request_id = l_request.id and status_code = 'PENDING';
    update of_purchase_orders
       set status_code = 'CANCELLED',
           cancellation_reason = substr(trim(p_reason_text), 1, 1000),
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where purchase_request_id = l_request.id
       and status_code in ('DRAFT', 'ISSUED');
    update of_purchase_requests
       set status_code = 'CANCELLED',
           cancellation_reason = substr(trim(p_reason_text), 1, 1000),
           closed_at = systimestamp, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_REQUEST_CANCELLED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, l_request.status_code, 'CANCELLED',
      l_request.row_version, p_new_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end cancel_request;

  procedure create_order_draft(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_supplier_id            in  number,
    p_po_id                   out number,
    p_po_no                   out varchar2,
    p_po_row_version          out number,
    p_request_row_version     out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_actor_name varchar2(255 char);
    l_count      number;
  begin
    savepoint of_procurement_api_action;
    p_po_id := null; p_po_no := null; p_po_row_version := null;
    p_request_row_version := null;
    assert_procurement;
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code not in ('APPROVED', 'PARTIALLY_ORDERED') then
      fail(-20304, 'Order drafts require APPROVED or PARTIALLY_ORDERED status.');
    end if;
    select count(*) into l_count from of_suppliers
     where id = p_supplier_id and is_active = 'Y';
    if l_count <> 1 then fail(-20306, 'Supplier is missing or inactive.'); end if;
    l_actor_name := actor_name();
    p_po_no := business_number('PURCHASE_ORDER_PREFIX', 'PO');
    insert into of_purchase_orders (
      po_no, purchase_request_id, supplier_id, status_code,
      currency_code, total_amount, row_version, created_by, updated_by
    ) values (
      p_po_no, l_request.id, p_supplier_id, 'DRAFT',
      l_request.currency_code, 0, 1, l_actor_name, l_actor_name
    ) returning id, row_version into p_po_id, p_po_row_version;
    update of_purchase_requests
       set row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_request_row_version;
    audit_event(
      'PURCHASE_ORDER_CREATED', 'PURCHASE_ORDER', p_po_id, p_po_no,
      null, 'DRAFT', null, p_po_row_version, null, 0
    );
    audit_event(
      'PURCHASE_REQUEST_ORDER_DRAFT_ADDED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no,
      l_request.status_code, l_request.status_code,
      l_request.row_version, p_request_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end create_order_draft;

  procedure add_order_item(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_request_item_id        in  number,
    p_ordered_quantity       in  number,
    p_unit_price             in  number,
    p_po_item_id             out number,
    p_new_po_version         out number
  ) is
    l_request       of_purchase_requests%rowtype;
    l_order         of_purchase_orders%rowtype;
    l_requested_qty number;
    l_already_qty   number;
    l_catalog_id    number;
    l_description   varchar2(1000 char);
    l_line_no       number;
    l_total         number;
    l_actor_name    varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_po_item_id := null; p_new_po_version := null;
    assert_procurement;
    lock_order(p_po_id, p_expected_po_version, l_request, l_order);
    if l_order.status_code <> 'DRAFT' then
      fail(-20304, 'Order items can be added only while the order is DRAFT.');
    end if;
    if l_request.status_code not in ('APPROVED', 'PARTIALLY_ORDERED') then
      fail(-20304, 'The owning request is not open for ordering.');
    end if;
    if p_ordered_quantity is null or p_ordered_quantity <= 0
       or p_unit_price is null or p_unit_price < 0 then
      fail(-20300, 'Ordered quantity must be positive and unit price nonnegative.');
    end if;
    if p_ordered_quantity <> round(p_ordered_quantity, 3)
       or p_unit_price <> round(p_unit_price, 2) then
      fail(-20300, 'Ordered quantity supports 3 decimals and unit price supports 2.');
    end if;
    begin
      select quantity, catalog_item_id, item_description
        into l_requested_qty, l_catalog_id, l_description
        from of_purchase_request_items
       where id = p_request_item_id
         and purchase_request_id = l_request.id;
    exception when no_data_found then
      fail(-20306, 'Request item does not belong to this request.');
    end;
    if l_catalog_id is null then
      fail(-20306, 'A catalog item is required before an item can be ordered.');
    end if;

    select coalesce(sum(oi.ordered_quantity), 0) into l_already_qty
      from of_purchase_order_items oi
      join of_purchase_orders o on o.id = oi.purchase_order_id
     where oi.request_item_id = p_request_item_id
       and o.status_code <> 'CANCELLED';
    if l_already_qty + p_ordered_quantity > l_requested_qty then
      fail(-20309, 'Ordered quantity exceeds the approved request remainder.');
    end if;
    select coalesce(max(line_no), 0) + 1 into l_line_no
      from of_purchase_order_items
     where purchase_order_id = l_order.id;
    l_actor_name := actor_name();
    insert into of_purchase_order_items (
      purchase_order_id, line_no, request_item_id, catalog_item_id,
      item_description, ordered_quantity, unit_price, line_total,
      created_by, updated_by
    ) values (
      l_order.id, l_line_no, p_request_item_id, l_catalog_id,
      l_description, p_ordered_quantity, p_unit_price,
      round(p_ordered_quantity * p_unit_price, 2),
      l_actor_name, l_actor_name
    ) returning id into p_po_item_id;
    l_total := order_total(l_order.id);
    update of_purchase_orders
       set total_amount = l_total, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_order.id
     returning row_version into p_new_po_version;
    audit_event(
      'PURCHASE_ORDER_ITEM_ADDED', 'PURCHASE_ORDER',
      l_order.id, l_order.po_no, 'DRAFT', 'DRAFT',
      l_order.row_version, p_new_po_version, l_order.total_amount, l_total
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end add_order_item;

  procedure issue_order(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_order_date             in  date,
    p_expected_date          in  date default null,
    p_new_po_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_order      of_purchase_orders%rowtype;
    l_line_count number;
    l_total      number;
    l_actor_id   number;
    l_actor_name varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_po_version := null; p_request_status := null;
    p_request_row_version := null;
    assert_procurement;
    lock_order(p_po_id, p_expected_po_version, l_request, l_order);
    if l_order.status_code <> 'DRAFT' then
      fail(-20304, 'Only a DRAFT order may be issued.');
    end if;
    if p_order_date is null then fail(-20300, 'Order date is required.'); end if;
    if p_expected_date is not null and p_expected_date < p_order_date then
      fail(-20300, 'Expected date cannot precede order date.');
    end if;
    select count(*) into l_line_count from of_purchase_order_items
     where purchase_order_id = l_order.id;
    if l_line_count = 0 then fail(-20307, 'At least one order item is required.'); end if;
    l_total := order_total(l_order.id);
    l_actor_id := actor_id(); l_actor_name := actor_name();
    update of_purchase_orders
       set status_code = 'ISSUED', order_date = p_order_date,
           expected_date = p_expected_date, total_amount = l_total,
           issued_by_user_id = l_actor_id, issued_at = systimestamp,
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_order.id
     returning row_version into p_new_po_version;
    p_request_status := ordering_status(l_request.id);
    update of_purchase_requests
       set status_code = p_request_status, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_request_row_version;
    audit_event(
      'PURCHASE_ORDER_ISSUED', 'PURCHASE_ORDER',
      l_order.id, l_order.po_no, 'DRAFT', 'ISSUED',
      l_order.row_version, p_new_po_version, l_order.total_amount, l_total
    );
    audit_event(
      'PURCHASE_REQUEST_ORDERING_UPDATED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, l_request.status_code, p_request_status,
      l_request.row_version, p_request_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end issue_order;

  procedure cancel_order(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_reason_text            in  varchar2,
    p_new_po_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_order      of_purchase_orders%rowtype;
    l_posted     number;
    l_actor_name varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_po_version := null; p_request_status := null;
    p_request_row_version := null;
    assert_text(p_reason_text, 'Order cancellation reason', 1000);
    assert_procurement;
    lock_order(p_po_id, p_expected_po_version, l_request, l_order);
    if l_order.status_code = 'ISSUED'
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'Cancelling an issued order requires operations admin.');
    elsif l_order.status_code not in ('DRAFT', 'ISSUED') then
      fail(-20304, 'Only a DRAFT or unreceived ISSUED order may be cancelled.');
    end if;
    select count(*) into l_posted from of_goods_receipts
     where purchase_order_id = l_order.id and status_code = 'POSTED';
    if l_posted > 0 then fail(-20304, 'An order with posted receipts cannot be cancelled.'); end if;
    l_actor_name := actor_name();
    update of_purchase_orders
       set status_code = 'CANCELLED',
           cancellation_reason = substr(trim(p_reason_text), 1, 1000),
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_order.id
     returning row_version into p_new_po_version;
    p_request_status := ordering_status(l_request.id);
    update of_purchase_requests
       set status_code = p_request_status, row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_request_row_version;
    audit_event(
      'PURCHASE_ORDER_CANCELLED', 'PURCHASE_ORDER',
      l_order.id, l_order.po_no, l_order.status_code, 'CANCELLED',
      l_order.row_version, p_new_po_version,
      l_order.total_amount, l_order.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end cancel_order;

  procedure close_order(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_new_po_version         out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_order      of_purchase_orders%rowtype;
    l_actor_name varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_po_version := null;
    assert_procurement;
    lock_order(p_po_id, p_expected_po_version, l_request, l_order);
    if l_order.status_code <> 'RECEIVED' then
      fail(-20304, 'Only a RECEIVED order may be closed.');
    end if;
    l_actor_name := actor_name();
    update of_purchase_orders
       set status_code = 'CLOSED', row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_order.id
     returning row_version into p_new_po_version;
    audit_event(
      'PURCHASE_ORDER_CLOSED', 'PURCHASE_ORDER',
      l_order.id, l_order.po_no, 'RECEIVED', 'CLOSED',
      l_order.row_version, p_new_po_version,
      l_order.total_amount, l_order.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end close_order;

  procedure close_request(
    p_request_id             in  number,
    p_expected_row_version   in  number,
    p_new_row_version        out number
  ) is
    l_request    of_purchase_requests%rowtype;
    l_open_count number;
    l_actor_name varchar2(255 char);
  begin
    savepoint of_procurement_api_action;
    p_new_row_version := null;
    assert_procurement;
    lock_request(p_request_id, p_expected_row_version, l_request);
    if l_request.status_code <> 'RECEIVED' then
      fail(-20304, 'Only a RECEIVED request may be closed.');
    end if;
    select count(*) into l_open_count from of_purchase_orders
     where purchase_request_id = l_request.id
       and status_code not in ('CLOSED', 'CANCELLED');
    if l_open_count > 0 then
      fail(-20304, 'Every noncancelled purchase order must be CLOSED first.');
    end if;
    l_actor_name := actor_name();
    update of_purchase_requests
       set status_code = 'CLOSED', closed_at = systimestamp,
           row_version = row_version + 1,
           updated_at = systimestamp, updated_by = l_actor_name
     where id = l_request.id
     returning row_version into p_new_row_version;
    audit_event(
      'PURCHASE_REQUEST_CLOSED', 'PURCHASE_REQUEST',
      l_request.id, l_request.request_no, 'RECEIVED', 'CLOSED',
      l_request.row_version, p_new_row_version,
      l_request.total_amount, l_request.total_amount
    );
  exception when others then
    rollback to of_procurement_api_action; raise;
  end close_request;
end of_procurement_api;
/

--------------------------------------------------------------------------------
-- 04. Public inventory transaction contract (4 actions)
--------------------------------------------------------------------------------

create or replace package of_inventory_api authid definer as
  procedure create_receipt_draft(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_received_at            in  timestamp with local time zone,
    p_delivery_reference     in  varchar2 default null,
    p_notes                  in  varchar2 default null,
    p_idempotency_key        in  varchar2,
    p_receipt_id             out number,
    p_receipt_no             out varchar2,
    p_receipt_row_version    out number
  );

  procedure add_receipt_item(
    p_receipt_id             in  number,
    p_expected_row_version   in  number,
    p_po_item_id             in  number,
    p_quantity_received      in  number,
    p_quantity_accepted      in  number,
    p_quantity_rejected      in  number,
    p_unit_cost              in  number,
    p_location_id            in  number,
    p_rejection_reason       in  varchar2 default null,
    p_receipt_item_id        out number,
    p_new_row_version        out number
  );

  procedure post_receipt(
    p_receipt_id             in  number,
    p_expected_row_version   in  number,
    p_idempotency_key        in  varchar2,
    p_new_row_version        out number,
    p_po_status              out varchar2,
    p_po_row_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  );

  procedure void_receipt(
    p_receipt_id             in  number,
    p_expected_row_version   in  number,
    p_reason_text            in  varchar2,
    p_new_row_version        out number,
    p_po_status              out varchar2,
    p_po_row_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  );
end of_inventory_api;
/

--------------------------------------------------------------------------------
-- 05. Inventory implementation
--------------------------------------------------------------------------------

create or replace package body of_inventory_api as
  procedure fail(p_code in number, p_message in varchar2) is
  begin
    raise_application_error(p_code, p_message);
  end fail;

  procedure assert_text(
    p_value in varchar2, p_label in varchar2, p_max_length in number
  ) is
  begin
    if trim(p_value) is null then
      fail(-20300, p_label || ' is required.');
    end if;
    if length(trim(p_value)) > p_max_length then
      fail(-20300, p_label || ' exceeds ' || p_max_length || ' characters.');
    end if;
  end assert_text;

  function actor_id return number is
  begin
    of_security_api.assert_authenticated;
    return of_security_api.current_user_id();
  end actor_id;

  function actor_name return varchar2 is
  begin
    return of_security_api.current_username();
  end actor_name;

  procedure assert_procurement is
  begin
    of_security_api.assert_authenticated;
    if not of_security_api.is_procurement_officer()
       and not of_security_api.is_operations_admin() then
      fail(-20305, 'A procurement officer or operations administrator is required.');
    end if;
  end assert_procurement;

  function business_number return varchar2 is
    l_prefix varchar2(8 char);
  begin
    l_prefix := substr(
      of_util_api.normalize_code(
        of_util_api.get_setting_text('GOODS_RECEIPT_PREFIX', 'GR')
      ),
      1,
      8
    );
    if l_prefix is null or not regexp_like(l_prefix, '^[A-Z][A-Z0-9_]{0,7}$') then
      fail(-20300, 'Invalid business-number prefix setting GOODS_RECEIPT_PREFIX.');
    end if;
    return l_prefix || '-' || to_char(systimestamp, 'YYMMDDHH24MISSFF3') ||
           '-' || substr(of_util_api.new_correlation_id(), 1, 4);
  end business_number;

  function state_json(
    p_status in varchar2,
    p_version in number
  ) return clob is
    l_json json_object_t := json_object_t();
  begin
    if p_status is null then l_json.put_null('statusCode');
    else l_json.put('statusCode', p_status); end if;
    if p_version is null then l_json.put_null('rowVersion');
    else l_json.put('rowVersion', p_version); end if;
    return l_json.to_clob();
  end state_json;

  procedure audit_event(
    p_action_code in varchar2,
    p_entity_type in varchar2,
    p_entity_id in number,
    p_entity_key in varchar2,
    p_old_status in varchar2,
    p_new_status in varchar2,
    p_old_version in number,
    p_new_version in number
  ) is
    l_id varchar2(64 char);
  begin
    l_id := of_audit_api.record_event(
      p_action_code      => p_action_code,
      p_entity_type_code => p_entity_type,
      p_entity_id        => p_entity_id,
      p_entity_key       => p_entity_key,
      p_old_values_json  => state_json(p_old_status, p_old_version),
      p_new_values_json  => state_json(p_new_status, p_new_version)
    );
  end audit_event;

  procedure lock_order_hierarchy(
    p_po_id               in  number,
    p_expected_po_version in  number,
    p_request             out of_purchase_requests%rowtype,
    p_order               out of_purchase_orders%rowtype
  ) is
    l_request_id number;
    e_busy exception;
    pragma exception_init(e_busy, -54);
  begin
    if p_po_id is null or p_expected_po_version is null
       or p_expected_po_version < 1 then
      fail(-20300, 'Purchase order ID and expected row version are required.');
    end if;

    select purchase_request_id into l_request_id
      from of_purchase_orders
     where id = p_po_id;

    select * into p_request
      from of_purchase_requests
     where id = l_request_id
       for update nowait;

    select * into p_order
      from of_purchase_orders
     where id = p_po_id
       for update nowait;

    if p_order.row_version <> p_expected_po_version then
      fail(-20302, 'Purchase order changed. Refresh and try again.');
    end if;
  exception
    when no_data_found then
      fail(-20301, 'Purchase order does not exist or is unavailable.');
    when e_busy then
      fail(-20303, 'Purchase request/order is being changed by another session.');
  end lock_order_hierarchy;

  procedure lock_receipt_hierarchy(
    p_receipt_id in number,
    p_request    out of_purchase_requests%rowtype,
    p_order      out of_purchase_orders%rowtype,
    p_receipt    out of_goods_receipts%rowtype
  ) is
    l_request_id number;
    l_po_id      number;
    e_busy exception;
    pragma exception_init(e_busy, -54);
  begin
    if p_receipt_id is null then
      fail(-20300, 'Goods receipt ID is required.');
    end if;

    select gr.purchase_order_id, po.purchase_request_id
      into l_po_id, l_request_id
      from of_goods_receipts gr
      join of_purchase_orders po on po.id = gr.purchase_order_id
     where gr.id = p_receipt_id;

    select * into p_request
      from of_purchase_requests
     where id = l_request_id
       for update nowait;

    select * into p_order
      from of_purchase_orders
     where id = l_po_id
       for update nowait;

    select * into p_receipt
      from of_goods_receipts
     where id = p_receipt_id
       for update nowait;
  exception
    when no_data_found then
      fail(-20301, 'Goods receipt does not exist or is unavailable.');
    when e_busy then
      fail(-20303, 'Purchase request/order/receipt is being changed by another session.');
  end lock_receipt_hierarchy;

  function posted_accepted(
    p_po_item_id        in number,
    p_exclude_receipt_id in number default null
  ) return number is
    l_quantity number;
  begin
    select coalesce(sum(gri.quantity_accepted), 0)
      into l_quantity
      from of_goods_receipt_items gri
      join of_goods_receipts gr on gr.id = gri.goods_receipt_id
     where gri.purchase_order_item_id = p_po_item_id
       and gr.status_code = 'POSTED'
       and (p_exclude_receipt_id is null or gr.id <> p_exclude_receipt_id);
    return l_quantity;
  end posted_accepted;

  procedure apply_balance(
    p_catalog_item_id in number,
    p_location_id     in number,
    p_quantity_delta  in number,
    p_actor_name      in varchar2
  ) is
    l_balance_id number;
    l_quantity   number;
  begin
    begin
      select id, quantity_on_hand
        into l_balance_id, l_quantity
        from of_inventory_balances
       where catalog_item_id = p_catalog_item_id
         and location_id = p_location_id
         for update;

      if l_quantity + p_quantity_delta < 0 then
        fail(-20311, 'Inventory reversal would make the on-hand balance negative.');
      end if;

      update of_inventory_balances
         set quantity_on_hand = quantity_on_hand + p_quantity_delta,
             row_version = row_version + 1,
             updated_at = systimestamp,
             updated_by = p_actor_name
       where id = l_balance_id;
    exception
      when no_data_found then
        if p_quantity_delta < 0 then
          fail(-20311, 'Inventory balance is missing for the reversal.');
        end if;
        insert into of_inventory_balances (
          catalog_item_id, location_id, quantity_on_hand,
          created_by, updated_by
        ) values (
          p_catalog_item_id, p_location_id, p_quantity_delta,
          p_actor_name, p_actor_name
        );
    end;
  end apply_balance;

  function derived_order_status(p_po_id in number) return varchar2 is
    l_line_count       number;
    l_incomplete_count number;
    l_accepted_total   number;
  begin
    select count(*),
           coalesce(sum(case when accepted_quantity < ordered_quantity
                             then 1 else 0 end), 0),
           coalesce(sum(accepted_quantity), 0)
      into l_line_count, l_incomplete_count, l_accepted_total
      from (
        select poi.id, poi.ordered_quantity,
               coalesce(sum(
                 case when gr.status_code = 'POSTED'
                      then gri.quantity_accepted else 0 end
               ), 0) accepted_quantity
          from of_purchase_order_items poi
          left join of_goods_receipt_items gri
            on gri.purchase_order_item_id = poi.id
          left join of_goods_receipts gr
            on gr.id = gri.goods_receipt_id
         where poi.purchase_order_id = p_po_id
         group by poi.id, poi.ordered_quantity
      );

    if l_line_count > 0 and l_incomplete_count = 0 then
      return 'RECEIVED';
    elsif l_accepted_total > 0 then
      return 'PARTIALLY_RECEIVED';
    else
      return 'ISSUED';
    end if;
  end derived_order_status;

  function derived_request_status(p_request_id in number) return varchar2 is
    l_active_orders     number;
    l_not_received      number;
    l_accepted_total    number;
    l_request_line_count number;
    l_underordered      number;
  begin
    select count(*),
           coalesce(sum(case when status_code not in ('RECEIVED', 'CLOSED')
                             then 1 else 0 end), 0)
      into l_active_orders, l_not_received
      from of_purchase_orders
     where purchase_request_id = p_request_id
       and status_code <> 'CANCELLED'
       and status_code <> 'DRAFT';

    select coalesce(sum(gri.quantity_accepted), 0)
      into l_accepted_total
      from of_goods_receipt_items gri
      join of_goods_receipts gr
        on gr.id = gri.goods_receipt_id and gr.status_code = 'POSTED'
      join of_purchase_order_items poi on poi.id = gri.purchase_order_item_id
      join of_purchase_orders po on po.id = poi.purchase_order_id
     where po.purchase_request_id = p_request_id
       and po.status_code <> 'CANCELLED';

    select count(*),
           coalesce(sum(case when ordered_quantity < requested_quantity
                             then 1 else 0 end), 0)
      into l_request_line_count, l_underordered
      from (
        select pri.id, pri.quantity requested_quantity,
               coalesce(sum(
                 case when po.status_code in (
                   'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CLOSED'
                 ) then poi.ordered_quantity else 0 end
               ), 0) ordered_quantity
          from of_purchase_request_items pri
          left join of_purchase_order_items poi on poi.request_item_id = pri.id
          left join of_purchase_orders po on po.id = poi.purchase_order_id
         where pri.purchase_request_id = p_request_id
         group by pri.id, pri.quantity
      );

    if l_request_line_count > 0 and l_underordered = 0
       and l_active_orders > 0 and l_not_received = 0 then
      return 'RECEIVED';
    elsif l_accepted_total > 0 then
      return 'PARTIALLY_RECEIVED';
    elsif l_request_line_count > 0 and l_underordered = 0 then
      return 'ORDERED';
    else
      return 'PARTIALLY_ORDERED';
    end if;
  end derived_request_status;

  procedure refresh_receiving_states(
    p_request       in  of_purchase_requests%rowtype,
    p_order         in  of_purchase_orders%rowtype,
    p_po_status     out varchar2,
    p_po_row_version out number,
    p_request_status out varchar2,
    p_request_row_version out number
  ) is
    l_actor_name          varchar2(255 char);
  begin
    l_actor_name := actor_name();
    p_po_status := derived_order_status(p_order.id);
    p_po_row_version := p_order.row_version;

    if p_order.status_code <> p_po_status then
      update of_purchase_orders
         set status_code = p_po_status,
             row_version = row_version + 1,
             updated_at = systimestamp,
             updated_by = l_actor_name
       where id = p_order.id
       returning row_version into p_po_row_version;

      audit_event(
        'PURCHASE_ORDER_RECEIVING_STATE', 'PURCHASE_ORDER',
        p_order.id, p_order.po_no, p_order.status_code, p_po_status,
        p_order.row_version, p_po_row_version
      );
    end if;

    p_request_status := derived_request_status(p_request.id);
    p_request_row_version := p_request.row_version;
    if p_request.status_code <> p_request_status then
      update of_purchase_requests
         set status_code = p_request_status,
             closed_at = null,
             row_version = row_version + 1,
             updated_at = systimestamp,
             updated_by = l_actor_name
       where id = p_request.id
       returning row_version into p_request_row_version;

      audit_event(
        'PURCHASE_REQUEST_RECEIVING_STATE', 'PURCHASE_REQUEST',
        p_request.id, p_request.request_no,
        p_request.status_code, p_request_status,
        p_request.row_version, p_request_row_version
      );
    end if;
  end refresh_receiving_states;

  procedure create_receipt_draft(
    p_po_id                  in  number,
    p_expected_po_version    in  number,
    p_received_at            in  timestamp with local time zone,
    p_delivery_reference     in  varchar2 default null,
    p_notes                  in  varchar2 default null,
    p_idempotency_key        in  varchar2,
    p_receipt_id             out number,
    p_receipt_no             out varchar2,
    p_receipt_row_version    out number
  ) is
    l_request       of_purchase_requests%rowtype;
    l_order         of_purchase_orders%rowtype;
    l_existing      of_goods_receipts%rowtype;
    l_actor_id      number;
    l_actor_name    varchar2(255 char);
    l_key           varchar2(200 char);

    procedure return_existing is
    begin
      if l_existing.purchase_order_id <> p_po_id
         or l_existing.received_at <> p_received_at
         or nvl(l_existing.delivery_reference, chr(0)) <>
            nvl(trim(p_delivery_reference), chr(0))
         or nvl(l_existing.notes, chr(0)) <> nvl(trim(p_notes), chr(0)) then
        fail(-20310, 'Idempotency key was already used with a different receipt payload.');
      end if;
      p_receipt_id := l_existing.id;
      p_receipt_no := l_existing.receipt_no;
      p_receipt_row_version := l_existing.row_version;
    end return_existing;
  begin
    savepoint of_inventory_api_action;
    assert_procurement;
    assert_text(p_idempotency_key, 'Idempotency key', 200);
    if p_received_at is null then
      fail(-20300, 'Received timestamp is required.');
    end if;
    if length(trim(p_delivery_reference)) > 100 then
      fail(-20300, 'Delivery reference exceeds 100 characters.');
    end if;
    if length(trim(p_notes)) > 2000 then
      fail(-20300, 'Receipt notes exceed 2000 characters.');
    end if;
    l_key := trim(p_idempotency_key);

    begin
      select * into l_existing
        from of_goods_receipts
       where idempotency_key = l_key;
      return_existing;
      return;
    exception
      when no_data_found then null;
    end;

    lock_order_hierarchy(
      p_po_id, p_expected_po_version, l_request, l_order
    );
    if l_order.status_code not in ('ISSUED', 'PARTIALLY_RECEIVED') then
      fail(-20304, 'A receipt draft requires an ISSUED or PARTIALLY_RECEIVED order.');
    end if;

    l_actor_id := actor_id();
    l_actor_name := actor_name();
    p_receipt_no := business_number();

    begin
      insert into of_goods_receipts (
        receipt_no, purchase_order_id, status_code,
        received_by_user_id, received_at, delivery_reference,
        notes, idempotency_key, created_by, updated_by
      ) values (
        p_receipt_no, l_order.id, 'DRAFT',
        l_actor_id, p_received_at, trim(p_delivery_reference),
        trim(p_notes), l_key, l_actor_name, l_actor_name
      ) returning id, row_version into p_receipt_id, p_receipt_row_version;
    exception
      when dup_val_on_index then
        select * into l_existing
          from of_goods_receipts
         where idempotency_key = l_key;
        return_existing;
        return;
    end;

    audit_event(
      'GOODS_RECEIPT_CREATED', 'GOODS_RECEIPT',
      p_receipt_id, p_receipt_no, null, 'DRAFT', null, p_receipt_row_version
    );
  exception
    when others then
      rollback to of_inventory_api_action;
      raise;
  end create_receipt_draft;

  procedure add_receipt_item(
    p_receipt_id             in  number,
    p_expected_row_version   in  number,
    p_po_item_id             in  number,
    p_quantity_received      in  number,
    p_quantity_accepted      in  number,
    p_quantity_rejected      in  number,
    p_unit_cost              in  number,
    p_location_id            in  number,
    p_rejection_reason       in  varchar2 default null,
    p_receipt_item_id        out number,
    p_new_row_version        out number
  ) is
    l_request       of_purchase_requests%rowtype;
    l_order         of_purchase_orders%rowtype;
    l_receipt       of_goods_receipts%rowtype;
    l_ordered       number;
    l_catalog_id    number;
    l_count         number;
    l_actor_name    varchar2(255 char);
  begin
    savepoint of_inventory_api_action;
    assert_procurement;
    if p_expected_row_version is null or p_expected_row_version < 1
       or p_po_item_id is null or p_location_id is null then
      fail(-20300, 'Expected receipt version, order item, and location are required.');
    end if;
    if p_quantity_received is null or p_quantity_received <= 0
       or p_quantity_accepted is null or p_quantity_accepted < 0
       or p_quantity_rejected is null or p_quantity_rejected < 0
       or p_quantity_accepted + p_quantity_rejected <> p_quantity_received then
      fail(-20300, 'Received quantity must be positive and equal accepted plus rejected.');
    end if;
    if p_unit_cost is null or p_unit_cost < 0 then
      fail(-20300, 'Unit cost must be zero or greater.');
    end if;
    if p_quantity_received <> round(p_quantity_received, 3)
       or p_quantity_accepted <> round(p_quantity_accepted, 3)
       or p_quantity_rejected <> round(p_quantity_rejected, 3)
       or p_unit_cost <> round(p_unit_cost, 2) then
      fail(-20300, 'Receipt quantities support 3 decimals and unit cost supports 2.');
    end if;
    if p_quantity_rejected > 0 then
      assert_text(p_rejection_reason, 'Rejection reason', 1000);
    elsif length(trim(p_rejection_reason)) > 1000 then
      fail(-20300, 'Rejection reason exceeds 1000 characters.');
    end if;

    lock_receipt_hierarchy(p_receipt_id, l_request, l_order, l_receipt);
    if l_receipt.row_version <> p_expected_row_version then
      fail(-20302, 'Goods receipt changed. Refresh and try again.');
    end if;
    if l_receipt.status_code <> 'DRAFT' then
      fail(-20304, 'Receipt items may be added only while the receipt is DRAFT.');
    end if;

    begin
      select ordered_quantity, catalog_item_id
        into l_ordered, l_catalog_id
        from of_purchase_order_items
       where id = p_po_item_id
         and purchase_order_id = l_order.id;
    exception
      when no_data_found then
        fail(-20306, 'Purchase-order item does not belong to this order.');
    end;

    select count(*) into l_count
      from of_locations
     where id = p_location_id
       and is_active = 'Y';
    if l_count <> 1 then
      fail(-20306, 'Receiving location does not exist or is inactive.');
    end if;

    if posted_accepted(p_po_item_id) + p_quantity_accepted > l_ordered then
      fail(-20309, 'Accepted quantity exceeds the unreceived order quantity.');
    end if;

    l_actor_name := actor_name();
    begin
      insert into of_goods_receipt_items (
        goods_receipt_id, purchase_order_item_id,
        quantity_received, quantity_accepted, quantity_rejected,
        unit_cost, location_id, rejection_reason, created_by, updated_by
      ) values (
        l_receipt.id, p_po_item_id,
        p_quantity_received, p_quantity_accepted, p_quantity_rejected,
        p_unit_cost, p_location_id, trim(p_rejection_reason),
        l_actor_name, l_actor_name
      ) returning id into p_receipt_item_id;
    exception
      when dup_val_on_index then
        fail(-20307, 'This order item already exists on the receipt.');
    end;

    update of_goods_receipts
       set row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = l_actor_name
     where id = l_receipt.id
     returning row_version into p_new_row_version;

    audit_event(
      'GOODS_RECEIPT_ITEM_ADDED', 'GOODS_RECEIPT',
      l_receipt.id, l_receipt.receipt_no, 'DRAFT', 'DRAFT',
      l_receipt.row_version, p_new_row_version
    );
  exception
    when others then
      rollback to of_inventory_api_action;
      raise;
  end add_receipt_item;

  procedure post_receipt(
    p_receipt_id             in  number,
    p_expected_row_version   in  number,
    p_idempotency_key        in  varchar2,
    p_new_row_version        out number,
    p_po_status              out varchar2,
    p_po_row_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  ) is
    l_request        of_purchase_requests%rowtype;
    l_order          of_purchase_orders%rowtype;
    l_receipt        of_goods_receipts%rowtype;
    l_line_count     number;
    l_ordered        number;
    l_is_stocked     char(1 char);
    l_actor_id       number;
    l_actor_name     varchar2(255 char);
    l_correlation_id varchar2(64 char);
  begin
    savepoint of_inventory_api_action;
    assert_procurement;
    assert_text(p_idempotency_key, 'Idempotency key', 200);
    lock_receipt_hierarchy(p_receipt_id, l_request, l_order, l_receipt);

    if trim(p_idempotency_key) <> l_receipt.idempotency_key then
      fail(-20310, 'Idempotency key does not match this receipt.');
    end if;

    if l_receipt.status_code = 'POSTED' then
      p_new_row_version := l_receipt.row_version;
      p_po_status := l_order.status_code;
      p_po_row_version := l_order.row_version;
      p_request_status := l_request.status_code;
      p_request_row_version := l_request.row_version;
      return;
    elsif l_receipt.status_code = 'VOID' then
      fail(-20304, 'A void receipt cannot be posted.');
    end if;

    if p_expected_row_version is null
       or l_receipt.row_version <> p_expected_row_version then
      fail(-20302, 'Goods receipt changed. Refresh and try again.');
    end if;
    if l_order.status_code not in ('ISSUED', 'PARTIALLY_RECEIVED') then
      fail(-20304, 'Receipt posting requires an ISSUED or PARTIALLY_RECEIVED order.');
    end if;

    select count(*) into l_line_count
      from of_goods_receipt_items
     where goods_receipt_id = l_receipt.id;
    if l_line_count = 0 then
      fail(-20307, 'At least one receipt item is required before posting.');
    end if;

    for x in (
      select gri.id receipt_item_id, gri.purchase_order_item_id,
             gri.quantity_accepted, gri.location_id,
             poi.catalog_item_id, poi.ordered_quantity
        from of_goods_receipt_items gri
        join of_purchase_order_items poi
          on poi.id = gri.purchase_order_item_id
       where gri.goods_receipt_id = l_receipt.id
       order by poi.catalog_item_id, gri.location_id, gri.id
    ) loop
      l_ordered := x.ordered_quantity;
      if posted_accepted(x.purchase_order_item_id, l_receipt.id) +
         x.quantity_accepted > l_ordered then
        fail(-20309, 'Receipt posting would exceed an order-item quantity.');
      end if;
    end loop;

    l_actor_id := actor_id();
    l_actor_name := actor_name();
    l_correlation_id := of_util_api.new_correlation_id();

    for x in (
      select gri.id receipt_item_id, gri.quantity_accepted,
             gri.location_id, poi.catalog_item_id
        from of_goods_receipt_items gri
        join of_purchase_order_items poi
          on poi.id = gri.purchase_order_item_id
       where gri.goods_receipt_id = l_receipt.id
         and gri.quantity_accepted > 0
       order by poi.catalog_item_id, gri.location_id, gri.id
    ) loop
      select is_stocked into l_is_stocked
        from of_catalog_items
       where id = x.catalog_item_id
         and is_active = 'Y';

      if l_is_stocked = 'Y' then
        insert into of_stock_movements (
          catalog_item_id, location_id, movement_type_code,
          quantity_delta, receipt_item_id, occurred_at,
          performed_by_user_id, reason_text, correlation_id
        ) values (
          x.catalog_item_id, x.location_id, 'RECEIPT',
          x.quantity_accepted, x.receipt_item_id, l_receipt.received_at,
          l_actor_id, 'Posted receipt ' || l_receipt.receipt_no,
          l_correlation_id
        );
        apply_balance(
          x.catalog_item_id, x.location_id,
          x.quantity_accepted, l_actor_name
        );
      end if;
    end loop;

    update of_goods_receipts
       set status_code = 'POSTED',
           posted_at = systimestamp,
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = l_actor_name
     where id = l_receipt.id
     returning row_version into p_new_row_version;

    audit_event(
      'GOODS_RECEIPT_POSTED', 'GOODS_RECEIPT',
      l_receipt.id, l_receipt.receipt_no, 'DRAFT', 'POSTED',
      l_receipt.row_version, p_new_row_version
    );

    refresh_receiving_states(
      l_request, l_order, p_po_status, p_po_row_version,
      p_request_status, p_request_row_version
    );
  exception
    when no_data_found then
      rollback to of_inventory_api_action;
      fail(-20306, 'A referenced catalog item is missing or inactive.');
    when dup_val_on_index then
      rollback to of_inventory_api_action;
      fail(-20310, 'Receipt ledger entry already exists; refresh the receipt.');
    when others then
      rollback to of_inventory_api_action;
      raise;
  end post_receipt;

  procedure void_receipt(
    p_receipt_id             in  number,
    p_expected_row_version   in  number,
    p_reason_text            in  varchar2,
    p_new_row_version        out number,
    p_po_status              out varchar2,
    p_po_row_version         out number,
    p_request_status         out varchar2,
    p_request_row_version    out number
  ) is
    l_request        of_purchase_requests%rowtype;
    l_order          of_purchase_orders%rowtype;
    l_receipt        of_goods_receipts%rowtype;
    l_actor_id       number;
    l_actor_name     varchar2(255 char);
    l_correlation_id varchar2(64 char);
  begin
    savepoint of_inventory_api_action;
    of_security_api.assert_authenticated;
    if not of_security_api.is_operations_admin() then
      fail(-20305, 'Only an operations administrator may void a receipt.');
    end if;
    assert_text(p_reason_text, 'Void reason', 1000);
    if p_expected_row_version is null or p_expected_row_version < 1 then
      fail(-20300, 'Expected receipt row version is required.');
    end if;

    lock_receipt_hierarchy(p_receipt_id, l_request, l_order, l_receipt);
    if l_receipt.row_version <> p_expected_row_version then
      fail(-20302, 'Goods receipt changed. Refresh and try again.');
    end if;
    if l_receipt.status_code = 'VOID' then
      fail(-20304, 'Goods receipt is already VOID.');
    end if;

    l_actor_id := actor_id();
    l_actor_name := actor_name();
    l_correlation_id := of_util_api.new_correlation_id();

    if l_receipt.status_code = 'POSTED' then
      for x in (
        select sm.id movement_id, sm.catalog_item_id,
               sm.location_id, sm.quantity_delta, sm.receipt_item_id
          from of_stock_movements sm
          join of_goods_receipt_items gri on gri.id = sm.receipt_item_id
         where gri.goods_receipt_id = l_receipt.id
           and sm.movement_type_code = 'RECEIPT'
         order by sm.catalog_item_id, sm.location_id, sm.id
      ) loop
        apply_balance(
          x.catalog_item_id, x.location_id,
          -x.quantity_delta, l_actor_name
        );

        begin
          insert into of_stock_movements (
            catalog_item_id, location_id, movement_type_code,
            quantity_delta, receipt_item_id, related_movement_id,
            occurred_at, performed_by_user_id, reason_text, correlation_id
          ) values (
            x.catalog_item_id, x.location_id, 'ADJUSTMENT',
            -x.quantity_delta, x.receipt_item_id, x.movement_id,
            systimestamp, l_actor_id, trim(p_reason_text), l_correlation_id
          );
        exception
          when dup_val_on_index then
            fail(-20310, 'A reversal already exists for this receipt movement.');
        end;
      end loop;
    end if;

    update of_goods_receipts
       set status_code = 'VOID',
           notes = substr(
             case when trim(notes) is null then null else trim(notes) || chr(10) end ||
             'VOID: ' || trim(p_reason_text),
             1, 2000
           ),
           row_version = row_version + 1,
           updated_at = systimestamp,
           updated_by = l_actor_name
     where id = l_receipt.id
     returning row_version into p_new_row_version;

    audit_event(
      'GOODS_RECEIPT_VOIDED', 'GOODS_RECEIPT',
      l_receipt.id, l_receipt.receipt_no,
      l_receipt.status_code, 'VOID',
      l_receipt.row_version, p_new_row_version
    );

    refresh_receiving_states(
      l_request, l_order, p_po_status, p_po_row_version,
      p_request_status, p_request_row_version
    );
  exception
    when others then
      rollback to of_inventory_api_action;
      raise;
  end void_receipt;
end of_inventory_api;
/

--------------------------------------------------------------------------------
-- 06. Immutable inventory-ledger guard
--------------------------------------------------------------------------------

create or replace trigger of_stock_movement_guard_trg
  before update or delete on of_stock_movements
begin
  raise_application_error(
    -20320,
    'Stock movements are immutable; create a related reversing adjustment.'
  );
end;
/

--------------------------------------------------------------------------------
-- 07. Compact installation evidence
--------------------------------------------------------------------------------

select object_name, object_type, status
  from user_objects
 where object_name in (
   'OF_CATALOG_ITEMS', 'OF_SUPPLIERS', 'OF_PURCHASE_REQUESTS',
   'OF_PURCHASE_REQUEST_ITEMS', 'OF_APPROVALS', 'OF_PURCHASE_ORDERS',
   'OF_PURCHASE_ORDER_ITEMS', 'OF_GOODS_RECEIPTS',
   'OF_GOODS_RECEIPT_ITEMS', 'OF_STOCK_MOVEMENTS',
   'OF_INVENTORY_BALANCES', 'OF_PROCUREMENT_API',
   'OF_INVENTORY_API', 'OF_STOCK_MOVEMENT_GUARD_TRG'
 )
 order by object_type, object_name;

select 'P07_SETTINGS' seed_group, count(*) actual_count, 5 expected_count
  from of_app_settings
 where setting_code in (
   'PURCHASE_REQUEST_PREFIX', 'PURCHASE_ORDER_PREFIX',
   'GOODS_RECEIPT_PREFIX', 'PROCUREMENT_APPROVAL_THRESHOLD',
   'APPROVAL_DUE_DAYS'
 )
union all
select 'P07_CATALOG_ITEMS', count(*), 6
  from of_catalog_items
 where code in (
   'OFFICE_PAPER_A4', 'BLACK_TONER', 'USB_C_DOCK',
   'SAFETY_KIT', 'STANDARD_LAPTOP', 'OFFICE_CHAIR'
 )
union all
select 'P07_SUPPLIERS', count(*), 3
  from of_suppliers
 where supplier_code in ('NILE_TECH', 'DELTA_OFFICE', 'CAIRO_SUPPLY')
order by seed_group;

--------------------------------------------------------------------------------
-- End P07 installer. Expected SQL Scripts statements: 9.
--------------------------------------------------------------------------------
