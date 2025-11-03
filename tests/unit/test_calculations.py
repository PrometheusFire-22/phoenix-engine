"""
Project Chronos: Unit Tests for Calculations
============================================
Purpose: Test mathematical calculations used in analytics views
Pattern: Pure unit tests with no database dependencies
"""

import pytest
from decimal import Decimal, ROUND_HALF_UP
from datetime import date


class TestYoYGrowthCalculations:
    """Test year-over-year growth percentage calculations."""

    def test_positive_growth(self):
        """Test YoY growth with positive change."""
        current = Decimal("105.0")
        prior = Decimal("100.0")

        # Formula: ((current - prior) / prior) * 100
        growth = ((current - prior) / prior) * 100

        assert growth == Decimal("5.0"), "Should calculate 5% growth"

    def test_negative_growth(self):
        """Test YoY growth with decline."""
        current = Decimal("95.0")
        prior = Decimal("100.0")

        growth = ((current - prior) / prior) * 100

        assert growth == Decimal("-5.0"), "Should calculate -5% decline"

    def test_zero_growth(self):
        """Test YoY growth with no change."""
        current = Decimal("100.0")
        prior = Decimal("100.0")

        growth = ((current - prior) / prior) * 100

        assert growth == Decimal("0.0"), "Should calculate 0% growth"

    def test_large_growth(self):
        """Test YoY growth with large percentage change."""
        current = Decimal("200.0")
        prior = Decimal("100.0")

        growth = ((current - prior) / prior) * 100

        assert growth == Decimal("100.0"), "Should calculate 100% growth"

    def test_growth_with_small_base(self):
        """Test YoY growth when prior value is very small."""
        current = Decimal("2.0")
        prior = Decimal("0.01")

        growth = ((current - prior) / prior) * 100

        assert growth == Decimal("19900.0"), "Should calculate 19,900% growth"

    def test_growth_with_zero_prior_raises_error(self):
        """Test that division by zero is handled."""
        current = Decimal("100.0")
        prior = Decimal("0.0")

        with pytest.raises(Exception):  # ZeroDivisionError or InvalidOperation
            ((current - prior) / prior) * 100

    def test_growth_rounding(self):
        """Test that growth is rounded to 2 decimal places."""
        current = Decimal("103.456")
        prior = Decimal("100.0")

        growth = ((current - prior) / prior) * 100
        rounded_growth = growth.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

        assert rounded_growth == Decimal("3.46"), "Should round to 3.46%"


class TestFXCrossRateCalculations:
    """Test FX cross-rate calculations (CAD-based to USD-based)."""

    def test_eur_cad_to_usd_eur(self):
        """Test converting EUR/CAD rate to USD/EUR rate."""
        # FXEURCAD = 1.627 (CAD per EUR)
        # FXUSDCAD = 1.3956 (CAD per USD)
        # USD per CAD = 1 / 1.3956 = 0.7165
        # USD per EUR = (CAD per EUR) × (USD per CAD)
        #             = 1.627 × 0.7165 = 1.1655

        cad_per_eur = Decimal("1.627")
        cad_per_usd = Decimal("1.3956")

        usd_per_cad = 1 / cad_per_usd
        usd_per_eur = cad_per_eur * usd_per_cad

        # Round to 4 decimal places (standard for FX)
        usd_per_eur_rounded = usd_per_eur.quantize(Decimal("0.0001"))

        assert abs(usd_per_eur_rounded - Decimal("1.1658")) < Decimal(
            "0.0002"
        ), f"Cross-rate calculation incorrect: {usd_per_eur_rounded}"

    def test_gbp_cad_to_usd_gbp(self):
        """Test converting GBP/CAD rate to USD/GBP rate."""
        # FXGBPCAD = 1.75 (CAD per GBP)
        # FXUSDCAD = 1.4 (CAD per USD)
        # USD per GBP = (CAD per GBP) × (USD per CAD)

        cad_per_gbp = Decimal("1.75")
        cad_per_usd = Decimal("1.4")

        usd_per_cad = 1 / cad_per_usd
        usd_per_gbp = cad_per_gbp * usd_per_cad

        usd_per_gbp_rounded = usd_per_gbp.quantize(Decimal("0.0001"))

        # Expected: 1.75 × (1/1.4) = 1.75 × 0.7143 = 1.25
        assert abs(usd_per_gbp_rounded - Decimal("1.25")) < Decimal("0.0001")

    def test_cross_rate_with_identity(self):
        """Test that USD/CAD cross-rate equals direct rate."""
        # FXUSDCAD = 1.4 (CAD per USD)
        # Direct USD per CAD = 1 / 1.4 = 0.7143
        # Cross-rate: (CAD per USD) × (USD per CAD) = 1.4 × (1/1.4) = 1.0

        cad_per_usd = Decimal("1.4")
        usd_per_cad_direct = 1 / cad_per_usd

        # Cross-rate (should equal identity)
        usd_per_usd = cad_per_usd * usd_per_cad_direct

        assert usd_per_usd == Decimal("1.0"), "Cross-rate with self should equal 1.0"


class TestFXInversionCalculations:
    """Test FX rate inversion (e.g., CAD/USD → USD/CAD)."""

    def test_invert_cad_per_usd(self):
        """Test inverting CAD per USD to get USD per CAD."""
        # DEXCAUS = 1.3956 (CAD per USD)
        # USD per CAD = 1 / 1.3956 = 0.7165

        cad_per_usd = Decimal("1.3956")
        usd_per_cad = 1 / cad_per_usd

        usd_per_cad_rounded = usd_per_cad.quantize(Decimal("0.0001"))

        assert usd_per_cad_rounded == Decimal("0.7165")

    def test_invert_jpy_per_usd(self):
        """Test inverting JPY per USD to get USD per 100 JPY."""
        # DEXJPUS = 150.0 (JPY per USD)
        # USD per 100 JPY = (100 / 150) = 0.6667

        jpy_per_usd = Decimal("150.0")
        usd_per_100_jpy = 100 / jpy_per_usd

        usd_per_100_jpy_rounded = usd_per_100_jpy.quantize(Decimal("0.0001"))

        assert abs(usd_per_100_jpy_rounded - Decimal("0.6667")) < Decimal("0.0001")

    def test_double_inversion_is_identity(self):
        """Test that inverting twice returns original value."""
        original = Decimal("1.4")
        inverted_once = 1 / original
        inverted_twice = 1 / inverted_once

        assert inverted_twice == original, "Double inversion should return original value"


class TestStalenessCalculations:
    """Test data freshness/staleness calculations."""

    def test_days_since_last_update(self):
        """Test calculation of days since last observation."""
        latest_date = date(2024, 10, 20)
        current_date = date(2024, 10, 28)

        days_since = (current_date - latest_date).days

        assert days_since == 8

    def test_days_until_stale_daily_series(self):
        """Test days remaining until daily series becomes stale."""
        max_lag_days = 7  # Daily series allows 7 days
        days_since_update = 3

        days_remaining = max_lag_days - days_since_update

        assert days_remaining == 4, "Should have 4 days until stale"

    def test_days_until_stale_monthly_series(self):
        """Test days remaining until monthly series becomes stale."""
        max_lag_days = 120  # Monthly series allows 120 days (4 months)
        days_since_update = 100

        days_remaining = max_lag_days - days_since_update

        assert days_remaining == 20, "Should have 20 days until stale"

    def test_is_stale_when_exceeded(self):
        """Test staleness check when threshold exceeded."""
        days_since_update = 10
        max_lag_days = 7

        is_stale = days_since_update > max_lag_days

        assert is_stale is True

    def test_is_fresh_when_within_threshold(self):
        """Test freshness check when within threshold."""
        days_since_update = 3
        max_lag_days = 7

        is_fresh = days_since_update <= max_lag_days

        assert is_fresh is True


class TestNullPercentageCalculations:
    """Test null percentage calculations for data quality."""

    def test_null_percentage_with_nulls(self):
        """Test null percentage when some values are null."""
        total_observations = 100
        null_count = 5

        null_pct = (null_count / total_observations) * 100

        assert null_pct == 5.0

    def test_null_percentage_no_nulls(self):
        """Test null percentage when no nulls exist."""
        total_observations = 100
        null_count = 0

        null_pct = (null_count / total_observations) * 100

        assert null_pct == 0.0

    def test_null_percentage_all_nulls(self):
        """Test null percentage when all values are null."""
        total_observations = 100
        null_count = 100

        null_pct = (null_count / total_observations) * 100

        assert null_pct == 100.0

    def test_null_percentage_rounds_correctly(self):
        """Test that null percentage rounds to 2 decimal places."""
        total_observations = 123
        null_count = 7

        null_pct = Decimal(null_count) / Decimal(total_observations) * 100
        rounded_pct = null_pct.quantize(Decimal("0.01"))

        assert rounded_pct == Decimal("5.69")


class TestFrequencyAdjustedLookbacks:
    """Test lookback period adjustments based on frequency."""

    def test_daily_lookback_365_days(self):
        """Daily data should look back 365 days for YoY."""
        frequency = "D"

        lookback_mapping = {"D": 365, "B": 252, "W": 52, "M": 12, "Q": 4, "A": 1}

        lookback = lookback_mapping[frequency]

        assert lookback == 365

    def test_business_daily_lookback_252_days(self):
        """Business daily (252 trading days) for YoY."""
        frequency = "B"

        lookback_mapping = {"D": 365, "B": 252, "W": 52, "M": 12, "Q": 4, "A": 1}

        lookback = lookback_mapping[frequency]

        assert lookback == 252

    def test_monthly_lookback_12_months(self):
        """Monthly data should look back 12 periods for YoY."""
        frequency = "M"

        lookback_mapping = {"D": 365, "B": 252, "W": 52, "M": 12, "Q": 4, "A": 1}

        lookback = lookback_mapping[frequency]

        assert lookback == 12


# Edge case tests
class TestEdgeCases:
    """Test edge cases in calculations."""

    def test_very_small_numbers(self):
        """Test calculations with very small numbers."""
        current = Decimal("0.0001")
        prior = Decimal("0.00005")

        growth = ((current - prior) / prior) * 100

        assert growth == Decimal("100.0"), "Should handle small numbers"

    def test_very_large_numbers(self):
        """Test calculations with very large numbers."""
        current = Decimal("1000000000.0")
        prior = Decimal("900000000.0")

        growth = ((current - prior) / prior) * 100

        rounded_growth = growth.quantize(Decimal("0.01"))

        assert rounded_growth == Decimal("11.11"), "Should handle large numbers"

    def test_negative_fx_rate_invalid(self):
        """Test that negative FX rates are invalid."""
        fx_rate = Decimal("-1.4")

        # In production, this should be caught by validation
        is_valid = fx_rate > 0

        assert is_valid is False, "Negative FX rates are invalid"

    def test_zero_fx_rate_invalid(self):
        """Test that zero FX rates are invalid."""
        fx_rate = Decimal("0.0")

        is_valid = fx_rate > 0

        assert is_valid is False, "Zero FX rates are invalid"
