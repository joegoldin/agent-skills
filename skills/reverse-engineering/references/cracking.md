# Password and hash cracking

Wordlists and rules are exposed as a stable dir-of-symlinks at `wordlists/` in
your working directory (gitignored, points into the Nix store), so no
`/nix/store` spelunking. Contents: `wordlists/rockyou.txt`,
`wordlists/seclists/` (full SecLists tree), `wordlists/best64.rule`,
`wordlists/hashcat-rules/`, `wordlists/john-rules/`, `wordlists/john-password.lst`.
To add more, edit the `wordlists` linkFarm in `flake.nix`.

| Command | What it does |
|---------|--------------|
| `hashcat -m 0 -a 0 hash.txt wordlists/rockyou.txt -r wordlists/best64.rule` | GPU/CPU password recovery |
| `john --wordlist=wordlists/rockyou.txt hash.txt` | John the Ripper (Jumbo); bundles `*2john` converters like `zip2john` |
