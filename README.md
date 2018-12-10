# gitlab-registry-cicd-cleanup

Gitlab registry &amp; CI/CD diskspace cleanup
Anders Nordby <anders@fupp.net>, 2018-12-07

# ABOUT

Removes old artifacts and registry images from Gitlab to preserve
diskspace (and make backup/restore a lesser burden):

- use Gitlab deployments API to check which images are in use and was
in use, keeping the last n number of images per environment. That way
you don't risk deleting images you are actively using or was using short
time ago.

- use Gitlab jobs API for getting rid of jobs with artifacts that don't
have expire set for artifacts. This takes up a lot of diskspace over
time also. And it gives developers an incentive in using artifacts expiry
to keep their old jobs around if they have any interest in that.

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
