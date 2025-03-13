from ethereum.crypto.alt_bn128 import BNF12


class TestAltBn128:
    def test_FROBENIUS_COEFFICIENTS(self, cairo_run):
        cairo_coeffs = cairo_run("FROBENIUS_COEFFICIENTS")
        assert len(cairo_coeffs) == 12
        frob_coeffs = tuple(BNF12(BNF12.FROBENIUS_COEFFICIENTS[i]) for i in range(12))
        assert all(cairo_coeffs[i] == coeff for i, coeff in enumerate(frob_coeffs))

    def test_BNF12_W(self, cairo_run):
        cairo_w = cairo_run("BNF12_W")
        assert cairo_w == BNF12.w

    def test_BNF12_W_POW_2(self, cairo_run):
        cairo_w_pow_2 = cairo_run("BNF12_W_POW_2")
        assert cairo_w_pow_2 == BNF12.w**2

    def test_BNF12_W_POW_3(self, cairo_run):
        cairo_w_pow_3 = cairo_run("BNF12_W_POW_3")
        assert cairo_w_pow_3 == BNF12.w**3

    def test_BNF12_I_PLUS_9(self, cairo_run):
        cairo_i_plus_9 = cairo_run("BNF12_I_PLUS_9")
        assert cairo_i_plus_9 == BNF12.i_plus_9
