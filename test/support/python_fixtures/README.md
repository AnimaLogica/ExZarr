# Python Zarr Fixture Generator for ExZarr v1.2.0

Generates tiny deterministic Zarr stores and a manifest for CI interoperability.

## Usage

```bash
# Zarr v2
python3 -m venv .venv-zarr2 && . .venv-zarr2/bin/activate
pip install 'zarr>=2.10,<3' numpy
python test/support/python_fixtures/generate_fixtures.py --out test/support/python_fixtures/generated/v2 --zarr-major 2

# Zarr v3 (pin one of 3.2 / 3.3 / 3.4)
python3 -m venv .venv-zarr34 && . .venv-zarr34/bin/activate
pip install 'zarr==3.4.*' numpy
python test/support/python_fixtures/generate_fixtures.py --out test/support/python_fixtures/generated/v3_3_4 --zarr-major 3
```

Manifest JSON records generator version, fixture names, and expected checksums.
