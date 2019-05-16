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
also understandable code wise. Try the dryrun option first.

PS: There are some issues with projects that do not get data about
deployments in the API. This seems to happen when environment info per
deployment stage in .gitlab-ci.yml is incomplete: add name and a valid
URL. Check your logs from this script for "Project has less than n
deployments (y). Skip deleting anything". In these project you both
want to look at .gitlab-ci.yml to make sure you get data in deployments
API for deployments (necessary to have images deleted) and if you have
used earlier versions of this script you may need to rebuild images that
were deleted prematurely.

Issue 42122
"Deployments are not created when the url doesn't start with 'http://'"
https://gitlab.com/gitlab-org/gitlab-ce/issues/42122

Issue 26537
Deployment is not created if two environments sharing the same external_url
https://gitlab.com/gitlab-org/gitlab-ce/issues/26537

Issue 2814
GitlabCI deployments are not created despite a successful job
https://gitlab.com/gitlab-com/support-forum/issues/2814

# HISTORY

2019-01-29: Add fix for projects with images in registry but no data in
deployments API. From now on we do not delete images in projects where
there is less than $minimum_deployments (config) deployments.

2019-05-16: Do not strictly compare tags, otherwise some images may
accidentally get deleted.

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

Run the script without, or use options mentioned below.

```
Usage: gitlab-registry-cicd-cleanup.rb [options]
    -n, --dryrun                     Dryrun (no changes)
    -d, --debug                      Debug output
        --nodeployments              Skip deployments
        --nojobs                     Skip job artifacts
    -p, --project PROJECT            Project name regexp match
        --help                       Show this message
```

# TODO

- Make a config file?
- Per group/repo configuration for number of images/jobs?
- Anything else?
