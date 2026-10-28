# Verification

Choose checks that can catch a plausible failure introduced by the change.
Prose and cosmetic edits usually need inspection; behavior changes need focused
execution. Add regression tests for meaningful behavior or recurring defects,
using the project's existing test tools.

Run broader or end-to-end checks when a changed interface, shared dependency,
or deployment path creates a specific risk, or the project requires them.
Batch related low-risk edits before checking. Reuse passing results while their
relevant inputs remain unchanged.

Once the requested behavior and required checks pass, finish. Another check
needs changed inputs, new evidence, or a named risk the earlier checks missed.
If a check cannot run, state what remains unverified and continue independent
work. Keep required merge and release gates in place.
