-- 20260818T000000_add_projects_vinyl_source.sql
--
-- VINYL ORDER RECORD (2026-08-18): where a job's vinyl actually came from.
--
-- A job's vinyl can be handled two ways: an order placed with a supplier, or
-- material pulled off the shop rack. Both end the same way — the job leaves the
-- VINYL ORDERS board — so this is a property of ONE act, recorded alongside the
-- existing marker columns.
--
-- WHY A NEW COLUMN RATHER THAN A THIRD vinyl_order_status VALUE:
--   • projects_vinyl_order_status_check admits only 'not_ordered' | 'ordered'.
--   • Every SHIPPED iOS build decodes an unrecognised status as `.notOrdered`
--     (ProjectVinylOrderStatus(rawValue:) ?? .notOrdered), which would put a
--     fully handled job BACK on the procurement board and invite a duplicate
--     order on real customer data.
-- So vinyl_order_status stays 'ordered' for both dispositions and this column
-- carries the distinction. Additive + nullable — older builds never read it and
-- are completely unaffected (schema discipline: 03_DATA_ARCHITECTURE.md).
--
-- Written by every MARK ORDERED path in the same atomic updateProjectFields
-- payload as the vinyl_order_status trio (DeckMaterialsOrderService.markerFields);
-- CLEAR ORDERED nulls it together with color and PO.
--
-- NULL means "not recorded": every row that predates this column was a supplier
-- order, and the client reads NULL as `.supplier` (VinylOrderDisposition
-- .fromColumnValue). No backfill is required or wanted.
--
-- !! NOT YET APPLIED. The iOS build that writes this column MUST NOT ship until
-- !! this migration is live, or every MARK ORDERED write fails on an unknown
-- !! column. Apply before merging the client change.

ALTER TABLE projects
  ADD COLUMN vinyl_source text NULL;

ALTER TABLE projects
  ADD CONSTRAINT projects_vinyl_source_check
  CHECK (vinyl_source IS NULL OR vinyl_source IN ('supplier', 'shop'));

COMMENT ON COLUMN projects.vinyl_source IS
  'Where the vinyl came from: supplier (an order was placed) or shop (pulled from stock). NULL = not recorded; treated as supplier. vinyl_order_status stays ''ordered'' for both.';
