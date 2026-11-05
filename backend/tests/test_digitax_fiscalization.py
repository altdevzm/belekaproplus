import os
from unittest.mock import Mock, patch

import requests

from app.services.digitax_service import DigiTaxZraService


def sale_config(api_key="live-key"):
    return {
        "digitax_api_key": api_key,
        "digitax_environment": "sandbox",
        "tpin": "1234567890",
        "sdc_id": "SDC-1",
    }


def sale_transaction():
    return {
        "transaction_uuid": "sale-123",
        "total_amount": 10.0,
        "cashier_id": "1001",
        "cashier_name": "Cashier",
    }


def sale_items():
    return [{
        "product_id": 1,
        "product_name": "Test item",
        "price_at_sale": 10.0,
        "quantity": 1,
        "zra_tax_code": "A",
        "tax_rate_at_sale": 16.0,
    }]


def test_missing_or_test_key_never_fabricates_receipt():
    with patch.dict(os.environ, {"DIGITAX_API_KEY": ""}), patch(
        "app.services.digitax_service.requests.post"
    ) as post:
        for key in (None, "test_key", "demo_key"):
            result = DigiTaxZraService.fiscalize_sale_invoice(
                sale_config(key), sale_transaction(), sale_items()
            )
            assert result["status"] == "PENDING"
            assert result.get("zra_receipt_number") is None
        post.assert_not_called()


def test_server_error_requires_reconciliation_without_receipt():
    response = Mock(status_code=503, text="service unavailable")
    with patch("app.services.digitax_service.requests.post", return_value=response):
        result = DigiTaxZraService.fiscalize_sale_invoice(
            sale_config(), sale_transaction(), sale_items()
        )

    assert result["status"] == "RECONCILIATION_REQUIRED"
    assert result.get("zra_receipt_number") is None


def test_conflict_requires_reconciliation():
    response = Mock(status_code=409, text="duplicate invoice")
    with patch("app.services.digitax_service.requests.post", return_value=response):
        result = DigiTaxZraService.fiscalize_sale_invoice(
            sale_config(), sale_transaction(), sale_items()
        )

    assert result["status"] == "RECONCILIATION_REQUIRED"
    assert result.get("zra_receipt_number") is None


def test_unknown_request_outcome_requires_reconciliation():
    with patch(
        "app.services.digitax_service.requests.post",
        side_effect=requests.Timeout("request timed out"),
    ):
        result = DigiTaxZraService.fiscalize_sale_invoice(
            sale_config(), sale_transaction(), sale_items()
        )

    assert result["status"] == "RECONCILIATION_REQUIRED"
    assert result.get("zra_receipt_number") is None


def test_success_without_receipt_requires_reconciliation():
    response = Mock(status_code=201, json=Mock(return_value={"id": "api-sale-1"}))
    with patch("app.services.digitax_service.requests.post", return_value=response):
        result = DigiTaxZraService.fiscalize_sale_invoice(
            sale_config(), sale_transaction(), sale_items()
        )

    assert result["status"] == "RECONCILIATION_REQUIRED"
    assert result.get("zra_receipt_number") is None


def test_success_without_mark_requires_reconciliation():
    response = Mock(
        status_code=201,
        json=Mock(return_value={"sdcReceiptNo": "INV/123"}),
    )
    with patch("app.services.digitax_service.requests.post", return_value=response):
        result = DigiTaxZraService.fiscalize_sale_invoice(
            sale_config(), sale_transaction(), sale_items()
        )

    assert result["status"] == "RECONCILIATION_REQUIRED"
    assert result.get("zra_receipt_number") is None


def test_confirmed_receipt_is_returned_as_success():
    response = Mock(
        status_code=201,
        json=Mock(return_value={
            "sdcReceiptNo": "INV/123",
            "vsdcMarkId": "signed-mark",
            "qrCodeUrl": "https://example.test/receipt",
        }),
    )
    with patch("app.services.digitax_service.requests.post", return_value=response):
        result = DigiTaxZraService.fiscalize_sale_invoice(
            sale_config(), sale_transaction(), sale_items()
        )

    assert result["status"] == "SUCCESS"
    assert result["zra_receipt_number"] == "INV/123"
    assert result["zra_mark_id"] == "signed-mark"


def test_credit_note_missing_key_never_fabricates_receipt():
    with patch.dict(os.environ, {"DIGITAX_API_KEY": ""}), patch(
        "app.services.digitax_service.requests.post"
    ) as post:
        result = DigiTaxZraService.fiscalize_refund_credit_note(
            sale_config(""), {"org_invoice_no": "INV/123"}, sale_items()
        )

    assert result["status"] == "PENDING"
    assert result.get("zra_receipt_number") is None
    post.assert_not_called()


def test_credit_note_success_without_receipt_metadata_requires_reconciliation():
    response = Mock(status_code=201, json=Mock(return_value={"id": "credit-note-1"}))
    with patch("app.services.digitax_service.requests.post", return_value=response):
        result = DigiTaxZraService.fiscalize_refund_credit_note(
            sale_config(), {"org_invoice_no": "INV/123"}, sale_items()
        )

    assert result["status"] == "RECONCILIATION_REQUIRED"
    assert result.get("zra_receipt_number") is None
