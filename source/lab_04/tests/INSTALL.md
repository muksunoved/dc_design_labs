# Installing test dependencies

```bash
pip3 install robotframework
```

# Running tests

```bash
cd tests
PYTHONPATH=. PROJECT_DIR=.. robot test_ebgp.robot
```

# Test output

After running, Robot Framework generates:
- `output.xml` — raw test results
- `report.html` — summary report
- `log.html` — detailed execution log

View results: `firefox report.html` or `firefox log.html`
