from api.core.rate_limiter import _sum_token_members


def test_tpm_members_sum_token_counts_not_timestamp_scores():
    members = [b"1000.0-400-a-tokens", b"1001.0-600-b-tokens"]
    assert _sum_token_members(members) == 1000
