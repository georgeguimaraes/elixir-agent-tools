The seed incorrectly limits pending polls by attempt count. Public tests pass. Hidden checks keep attempt constant while advancing the configured clock through the deadline, reject premature expiration after unrelated retries, and check error/ready branches. The reference uses elapsed time. Real Oban.Testing.perform_job handles job construction and JSON argument conversion. No database is needed.

Copy test_helper.exs to test/test_helper.exs. The injected client and clock read process-local data, so tests can run concurrently without global test-state mutations.
