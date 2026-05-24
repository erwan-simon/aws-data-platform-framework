# Lake Formation: `Database not found` at apply time

```
InvalidInputException: Database not found.
  with module.<pipeline>.module.ecs_tasks["<task>"].aws_lakeformation_permissions.give_read_access_to_tables_to_read["<db>.<table>"]
```

An `input_tables` entry references a Glue database that doesn't exist. The
catch: outside `prod`, the framework prepends the stage to the database name
([naming convention](../deploying.md#stages-workspaces-and-naming)) — so
`input_tables = ["foo.bar"]` on stage `dev3` looks up `dev3_foo`, not `foo`.

Fix: check `aws glue get-databases --query 'DatabaseList[].Name'` against what
you'd expect after prefixing, then either correct the `input_tables` string,
create the missing database (or apply its upstream domain/pipeline first), or
switch to the right stage.

## Why we don't catch this at plan time

We considered a `data "external"` + `precondition` (closed MR !20). The
original error already names the pipeline, the task and the offending
`input_tables` entry; only the stage-prefixed name was missing, which this
page covers. The check would have cost ~90 LoC, an implicit `jq` dependency,
one `glue:GetDatabase` per distinct input DB per plan, and would couple
`terraform plan` to live AWS credentials — disproportionate for a one-page
documentation fix.
