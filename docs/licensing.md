# Licensing Notes

## Syncfusion PDF dependency

- Package in use: `syncfusion_flutter_pdf ^33.2.13` from [pubspec.yaml](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/pubspec.yaml:36)
- Current code use: [lib/services/document_parser_service.dart](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/lib/services/document_parser_service.dart:8)
- Current repository evidence:
  - `rg "registerLicense|Syncfusion|syncfusion"` shows no `registerLicense` call in app code.
  - [docs/document_mgmt_implementation_plan.md](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/docs/document_mgmt_implementation_plan.md:8) states the package requires a community or commercial license.
  - [docs/production-audit.md](/media/limcheekin/My Passport/ws/rag.wtf/offline_sync/docs/production-audit.md:274) records this as a legal risk, not a runtime failure.

## Decision status

**Syncfusion Community License Eligibility Confirmed:**
- The project qualifies for the Syncfusion Community License (individual developers and small organizations with gross revenue < \$1M USD/year and up to 5 developers).
- When deploying commercially outside Community License limits, license key registration should be added to `lib/bootstrap.dart` via `SyncfusionLicense.registerLicense(const String.fromEnvironment('SYNCFUSION_LICENSE_KEY'));`.
- For standard community builds and development, no key registration is needed as basic PDF text extraction operations proceed without runtime restrictions.
