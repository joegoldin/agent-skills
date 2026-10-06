---
name: test-driven-development
description: Test-first workflow (red, green, refactor). Use when the user asks for TDD or test-first work, or when fixing a reproducible bug that has no failing test yet.
---

# Test-Driven Development

Write the test first, watch it fail for the right reason, then write the least
code that makes it pass. A test you never saw fail may not test what you think.

## The cycle

1. **Red.** Write one small test for the next behaviour: a clear name, real
   code, mocks only where a real dependency is impractical.
2. **Check red.** Run it. It should fail because the behaviour is missing,
   with the message you expect. If it passes, it is testing behaviour that
   already exists; if it errors, fix the error until it fails properly.
3. **Green.** Write the simplest code that passes. Don't add options or
   features the test does not ask for.
4. **Check green.** Run it and the neighbouring tests. Fix the code, not the
   test, when it fails.
5. **Refactor** while green: names, duplication, helpers. No new behaviour.

Repeat for the next behaviour. Done means each changed behaviour has a test
that failed first and now passes, and the suite around it is green.

For a bug, the first test reproduces it. That test is the proof of the fix and
the guard against its return.

## A good test

```typescript
test('retries failed operations 3 times', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('fail');
    return 'success';
  };

  expect(await retryOperation(operation)).toBe('success');
  expect(attempts).toBe(3);
});
```

It names one behaviour and exercises real code. Compare a test that only
checks a mock was called three times: it passes whatever `retryOperation`
does with the result.

| Quality | Good | Weak |
|---|---|---|
| One thing | splits "validates email and domain" in two | `test('validates email and domain and whitespace')` |
| Clear | the name states the behaviour | `test('test1')` |
| Shows intent | reads like the API you want | obscures what the code should do |

## When it's hard

| Problem | What it usually means |
|---|---|
| Don't know how to test it | Write the call you wish existed, then the assertion |
| The test is complicated | The interface is; simplify it |
| Everything has to be mocked | The code is too coupled; inject the dependency |
| Setup is huge | Extract helpers; if it is still huge, simplify the design |

Before adding mocks or test-only helpers, read testing-anti-patterns.md: it
covers testing mock behaviour, test-only methods in production code, and
mocking without understanding the dependency.
