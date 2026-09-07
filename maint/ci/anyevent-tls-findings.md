AnyEvent 7.17 Windows TLS test failure
====================================

The Windows CI blocker is the cleanup in AnyEvent's `t/80_ssltest.t`, mode 1.
The client releases its handle after its write buffer drains, without sending a
TLS close notification. The server receives the application line, then reports
a connection-aborted error where the test expects EOF.

The tested patch adds two lines before the existing cleanup:

```perl
$_[0]->on_drain (undef);
$_[0]->stoptls;
```

Clearing the drain callback prevents re-entry when `stoptls` writes the TLS
alert. AnyEvent's existing public API supplies the necessary shutdown behavior;
no AnyEvent library or Net::Nostr runtime code needs to change for this test.
The patch preserves all 415 original assertions and leaves TLS versions,
session tickets, and certificate settings unchanged.

See [the patch](patches/anyevent-7.17-tls-shutdown.patch). Applying it to a clean
AnyEvent 7.17 source tree with `patch -p1` was checked locally against the exact
candidate exercised by the diagnostic script.

Evidence
--------

- [Original Strawberry CI failure](https://github.com/NicholasBHubbard/Net-Nostr/actions/runs/34137431539/job/101791527200):
  only AnyEvent and its dependent AnyEvent::HTTP remain uninstalled. The failure
  is assertion 6 in `t/80_ssltest.t`; project tests have not started.
- [Shutdown comparisons](https://github.com/NicholasBHubbard/Net-Nostr/actions/runs/34141887297):
  Windows Strawberry Perl 5.42.2, macOS Perl 5.44.0, and Ubuntu Perl 5.44.0.
- [Full dependency and integration validation](https://github.com/NicholasBHubbard/Net-Nostr/actions/runs/34142422032):
  baseline reproduction, candidate repetitions, TLS message tracing, a normal
  cpanm test/install of the patched source, and Windows Net::Nostr suites.

The comparison ran each complete TLS test three times per platform:

| Cleanup | Windows | macOS | Ubuntu |
| --- | --- | --- | --- |
| Original immediate handle release | FAIL 3/3 | PASS 3/3 | PASS 3/3 |
| `stoptls`, then release | PASS 3/3 | PASS 3/3 | PASS 3/3 |
| TCP half-close, wait for peer EOF | PASS 3/3 | PASS 3/3 | PASS 3/3 |
| `stoptls`, wait for peer EOF | PASS 3/3 | PASS 3/3 | PASS 3/3 |
| `stoptls`, TCP half-close, wait for peer EOF | PASS 3/3 | PASS 3/3 | PASS 3/3 |

The wait-for-EOF variants add an assertion for the client's EOF callback.
The selected two-line patch keeps the existing 415-assertion plan.

The second run passes the full patched AnyEvent suite on all three platforms,
without forcing installation or skipping the TLS test. Extra instrumented tests
force TLS 1.3, enable two session tickets, and assert that tickets are sent and
the close notification is both sent and received. Those additional assertions
also pass on all three platforms. Windows uses Net::SSLeay 1.96 / OpenSSL 3.6.1;
macOS and Ubuntu use Net::SSLeay 1.92 / OpenSSL 3.6.3.

Protocol context
----------------

[AnyEvent::Handle documents `stoptls`](https://metacpan.org/pod/AnyEvent::Handle#%24handle-%3Estoptls)
as the method for sending a TLS close notification. It can invoke callbacks,
which is why the patch clears the drain callback first.

[RFC 8446 section 4.6.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-4.6.1)
permits the server to send session tickets after the handshake.
[Section 6.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-6.1) requires a
close notification before closing the write side, unless an error alert was
already sent. These requirements explain why an empty application write buffer
does not establish that abruptly releasing the socket will produce clean EOF.

In the Windows trace, the baseline error originates from the `sysread` error
path in `AnyEvent::Handle` (`Handle.pm:2030`, Perl errno 106). The trace records
two TLS 1.3 session tickets and no close alert. The patched trace records the
same two tickets plus one sent and one received `close_notify`, with no error.

The earlier ticket-disable/TLS-1.2 experiments isolated the trigger; the new
patch preserves TLS 1.3 and ticket coverage. The evidence confirms the missing
TLS close alert and the effect of fixing it. No TCP packet capture was taken,
so the exact Windows kernel packet/reset sequence is not established.

Scope and follow-up
-------------------

This work is isolated on `ci/anyevent-tls-investigation`. The normal CI workflow
and PR #1 are unchanged. The branch contains the diagnostic workflow, its Perl
driver, this report, and the proposed upstream test patch.

No public API, validation, POD, or distribution `Changes` modifications were
made. No NIPs were involved; TLS RFC sections and upstream API documentation
were consulted. Workflow lint, YAML parsing, Perl syntax, patch application, and
the remote tests described above were checked. Optional upstream backend and
network tests retain their normal skips.

AnyEvent 7.17 remains the latest release in MetaCPAN at the time of investigation.
The current upstream CVS copy of the test has the same executable code as 7.17.
An upgrade alone is therefore not currently available. The patch has not been
submitted upstream or added to the normal dependency installation workflow.
An eventual CI workaround should pin the upstream source and apply only this
test patch, then let the normal dependency test suite run before installation.

The Windows integration run successfully installs AnyEvent and AnyEvent::HTTP,
then runs the Core suite: 97 files, 3377 reported tests, one failing subtest.
The failure is `t/01-Key.t:136`: `save_privkey` expects file mode `0600` (384)
but Windows `stat` reports `0666` (438). The other 96 test files pass, including
all Core NIP conformance files.

This is a separate portability issue. `Key.pm:154` passes `0600` to `sysopen`,
and the method's POD promises owner-only read/write. Windows access controls
need separate examination; these mode bits alone do not establish the file's
effective ACL. The key round-trip checks pass. The Core author checks and the
Client, Relay, and shim suites were not reached because the workflow stops on
the Core failure. The diagnostic run therefore remains red even though the
AnyEvent patch passes all its validation gates.
