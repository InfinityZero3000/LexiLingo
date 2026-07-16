from tracecag_bench.catalog import MODES


def test_controller_ablation_modes_hold_backend_constant():
    names = ["l2_only", "exact_cache", "l0_l1_no_certificate", "l0_l1_certificate", "tracecag_full"]
    modes = [MODES[name] for name in names]

    assert {mode.ranker for mode in modes} == {"graph"}
    assert {mode.retrieval_policy for mode in modes} == {"full"}


def test_each_controller_ablation_has_the_declared_delta():
    assert MODES["l2_only"].controller_dict() == {
        "enable_l0": False, "enable_l1": False, "require_certificate": True,
        "enable_patch": False, "enable_recheck": False,
    }
    assert MODES["exact_cache"].enable_l0 is True
    assert MODES["exact_cache"].enable_l1 is False
    assert MODES["l0_l1_no_certificate"].require_certificate is False
    assert MODES["l0_l1_certificate"].enable_patch is False
    assert MODES["tracecag_full"].controller_dict() == {
        "enable_l0": True, "enable_l1": True, "require_certificate": True,
        "enable_patch": True, "enable_recheck": True,
    }
