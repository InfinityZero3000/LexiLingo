# Testing Guide 🧪

## Quick Start

```bash
# Run Phase 1 tests (RECOMMENDED)
./test_phase1.sh

# Or use flutter test directly
flutter test test/core/network/ test/features/auth/data/models/ test/features/auth/domain/usecases/
```

## Test Status

✅ **Phase 1**: 32/32 tests passing  
⚠️ **Old Files**: Compile errors (will be refactored)

See [TEST_STATUS.md](docs/TEST_STATUS.md) for details.

## Test Scripts

### `test_phase1.sh` ✅ RECOMMENDED
Runs only Phase 1 tests (excludes old files with errors)
```bash
./test_phase1.sh
```

### `test_script.sh` ⚠️ FULL SUITE
Runs all tests including old files (will have compile errors)
```bash
./test_script.sh
```

## Phase 1 Test Coverage

### Core Network (9 tests)
```bash
flutter test test/core/network/response_models_test.dart
```
- API envelope parsing
- Pagination handling
- Error classification

### Auth Models (15 tests)
```bash
flutter test test/features/auth/data/models/
```
- UserModel JSON mapping
- Auth tokens, device info
- Request/Response DTOs

### Auth UseCases (8 tests)
```bash
flutter test test/features/auth/domain/usecases/
```
- Register/Login business logic
- Error handling with Either<Failure, T>
- Mock repository integration

## Generating Mocks

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## VSCode Integration

Tests are configured in `.vscode/settings.json`:
- Press `F5` or click "Run Tests" in VSCode
- Only Phase 1 tests will run by default

## CI/CD Configuration

```yaml
# .github/workflows/test.yml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - uses: subosito/flutter-action@v2
    - run: flutter pub get
    - run: flutter pub run build_runner build --delete-conflicting-outputs
    - run: flutter test test/core/network/ test/features/auth/data/models/ test/features/auth/domain/usecases/
```

## Test Results

See [TEST_RESULTS.md](docs/TEST_RESULTS.md) for comprehensive test report.

## Known Issues

**Old files have compile errors** - these are NOT part of Phase 1:
- Old Course entity (missing)
- Old Firebase auth usecases
- Old vocabulary usecases

These will be refactored in Phase 2 to follow the new architecture pattern with `Either<Failure, T>`.

## Next Steps

1. ✅ Phase 1 Complete (32 tests passing)
2. [ ] Setup dependency injection
3. [ ] Backend integration tests
4. [ ] Phase 2: Course Management
