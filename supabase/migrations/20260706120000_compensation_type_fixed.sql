-- Add a 'fixed' compensation type (a guaranteed monthly amount ÷ cutoffs, not
-- reduced by undertime/absence). Widen the CHECK on all three tables that
-- carry compensation_type.
alter table public.employees drop constraint employees_compensation_type_check;
alter table public.employees add constraint employees_compensation_type_check
  check (compensation_type = any (array['hourly','daily','salaried','fixed']));

alter table public.employment_templates drop constraint employment_templates_compensation_type_check;
alter table public.employment_templates add constraint employment_templates_compensation_type_check
  check (compensation_type = any (array['hourly','daily','salaried','fixed']));

alter table public.payslips drop constraint payslips_compensation_type_check;
alter table public.payslips add constraint payslips_compensation_type_check
  check (compensation_type = any (array['hourly','daily','salaried','fixed']));
