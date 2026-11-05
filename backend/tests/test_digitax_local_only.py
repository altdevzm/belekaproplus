from unittest.mock import patch

from app.services.digitax_service import DigiTaxZraService


def test_local_only_product_is_not_registered():
    with patch("app.services.digitax_service.requests.post") as post:
        result = DigiTaxZraService.save_item(
            {"digitax_api_key": "live-key"},
            {"sku": "LOCAL-1", "name": "Local product", "stock_level": 5},
        )

    assert result["status"] == "SKIPPED"
    assert result["live_synced"] is False
    post.assert_not_called()


def test_batch_sync_does_not_register_or_adjust_local_only_products():
    with (
        patch("app.services.digitax_service.requests.post") as post,
        patch("app.services.digitax_service.requests.put") as put,
    ):
        result = DigiTaxZraService.batch_sync_items(
            {"digitax_api_key": "live-key"},
            [{
                "sku": "LOCAL-1",
                "name": "Local product",
                "stock_level": 5,
                "is_digitax_sync_enabled": False,
            }],
        )

    assert result["items"][0]["status"] == "SKIPPED"
    assert result["synced_count"] == 0
    post.assert_not_called()
    put.assert_not_called()
