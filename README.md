# gitlab-registry-cicd-cleanup

Gitlab registry &amp; CI/CD diskspace cleanup
Anders Nordby <anders@fupp.net>, 2018-12-07

WARNING: Use this at your own risk. Backup before you try it.
But I tried to implement this as cleanly and practical as possible, and
also understandable code wise.

# REQUIREMENTS

Requires Gitlab with API v4, minimum Gitlab v9.0. But this has only been
tested with Gitlab version 11+.

Otherwise you need:

- Ruby v2+

- Ruby gems:

```
gem install httparty
gem install json
```

# CONFIGURATION

See the configuration section in the script.

# USAGE

Just run the script:

```
./gitlab-registry-cicd-cleanup.rb
```

# TODO

- Make a config file?
- Per group/repo configuration for number of images/jobs?
- Anything else?
