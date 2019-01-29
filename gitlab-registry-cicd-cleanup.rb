#! /usr/bin/ruby
##
## THIS FILE IS UNDER PUPPET CONTROL. DON'T EDIT IT HERE.
##
# Gitlab registry & CI/CD diskspace cleanup
# Anders Nordby <anders@fupp.net>, 2018-12-07

# - Delete expired registry docker images: keep only last n per deployed
# environment.
# - Delete jobs & artifacts for jobs that have artifacts (consumes lots of
# disk space), if artifacts expire is not set -- except last n number of
# jobs per stage

# Install these with "gem install <extension>"
require "httparty"
require "json"
# These are included in Ruby installations
require "socket"
require "pp"
require "fileutils"
require 'optparse'

# Usage? Run the script with --help.

# Configuration
# Number of jobs with artifacts to keep per stage per project
$keepjobs=10
# Number of images from successful deploys per environment to keep per project
$keepimages=5
# Minimum number of deployments for image deletion to be done
# TODO: are they old/current?
$minimum_deployments=10
# Where your Gitlab registry is
# The default
$registry_path="/var/opt/gitlab/gitlab-rails/shared/registry"
# Our path - we keep a separate FS
#$registry_path="/var/gitlab-registry"

# Read token password from file
token=File.open("/usr/local/etc/gitlab/token.pwd").read.chomp
# Or just set it here
# Fixed API URL
#$apiurl="https://gitlab.foo.com/api/v4"
# API URL changing depending on which server it runs
hostname = Socket.gethostname
case hostname
when "gittest0.foo.com"
  $apiurl="https://gitlab-test.foo.com/api/v4"
when "gitprod0.foo.com"
  $apiurl="https://gitlab.foo.com/api/v4"
else
  fail "Unknown hostname #{hostname}."
end
# End Configuration

ARGV.push('--help') if ARGV.empty?
$options = {}
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: gitlab-registry-cicd-cleanup.rb [options]"

  opts.on("-n", "--dryrun", "Dryrun (no changes)") do |a|
    $options[:dryrun] = a
  end
  opts.on("-d", "--debug", "Debug output") do |a|
    $options[:debug] = a
  end
  opts.on("--nodeployments", "Skip deployments") do |a|
    $options[:nodeployments] = a
  end
  opts.on("--nojobs", "Skip job artifacts") do |a|
    $options[:nojobs] = a
  end
  opts.on("-p", "--project PROJECT", "Project name regexp match") do |a|
    $options[:project] = a
  end
  opts.on_tail("--help", "Show this message") do
    puts opts
    exit 3
  end
end.parse!

puts "----------"
puts "Performing gitlab registry/jobs cleanup [" + DateTime.now.strftime("%Y-%m-%d %H:%M:%S") + "]"

def pageget (upath)
  pdata = []
  url = "#{$apiurl}#{upath}/?per_page=100"
  response = HTTParty.get(url, :headers => $headers, :verify => false)
  jdata=JSON.parse(response.body)
  if response.code != 200
    puts "Got response code #{response.code.to_s} for URL #{url}"
    return pdata
  end

  npages = response.headers["X-Total-Pages"].to_i
  pdata.push(*jdata)

  if npages > 1
    page = 2
    loop do
      response = HTTParty.get("#{url}&page=#{page.to_s}", :headers => $headers, :verify => false)
      jdata = JSON.parse(response.body)
      pdata.push(*jdata)
      if page == npages
        break
      else
        page+=1
      end
    end
  end
  return pdata
end

def delete_artifact_jobs
  $projects.each do |p|
    id=p["id"]
    $gpath=p["path_with_namespace"]
    next if $options[:project] and $gpath !~ /#{$options[:project]}/
#    next unless $gpath == "CarPreparation/hvorerbilen-frontend"
    puts "Doing repo path: #{$gpath} project ID: #{id.to_s}"
    joblist = pageget("/projects/#{id}/jobs")

    # Split job list per stage. We want to keep n number of jobs per stage
    jobs = {}
    joblist.each do |job|
      jstage = job["stage"]
      jid = job["id"]
      if jstage == "" or jstage.nil?
        puts "Empty stage?"
        puts "Job id=#{jid} stage=#{jstage}"
      end
      if jobs[jstage].nil?
        jobs[jstage] = []
      end
      jobs[jstage].push(job)
    end

    if $options[:debug]
      puts "Data from jobs API:"
      pp joblist
      puts "Jobs per env:"
      pp jobs
    end

    puts "Number of jobs: #{joblist.length.to_s}"
    puts "Jobs per stage:"
    jobs.each_pair do |jstage,jslist|
      puts "#{jstage}: #{jslist.length.to_s}"
      ajobs = 0
      aeniljobs = 0
      njob = 1
      jslist.sort_by { |k| k["id"] }.reverse.each do |job|
        jid = job["id"]
        if njob > $keepjobs
          puts "Job ID: " + job["id"].to_s + " (delete?)"
          if job["artifacts_expire_at"].nil? and not job["artifacts"].empty? 
            puts "Really delete project ID #{id} job ID #{jid}, has artifacts and no artifacts_expire_at."
            if $options[:dryrun]
              puts "Skip deleting job due to dryrun mode."
            else
              puts "Do the delete for sure."
              delurl = "#{$apiurl}/projects/#{id}/jobs/#{jid}/erase"
              response = HTTParty.post(delurl, :headers => $headers, :verify => false)
              puts "Tried to delete job. Got response code: #{response.code.to_s}"
              puts "Used URL: #{delurl}"
              pp response.body
            end
          end
        else
          puts "Job ID: " + job["id"].to_s + " (keep)"
        end

        if not job["artifacts"].empty?
          ajobs += 1
          aeniljobs += 1 if job["artifacts_expire_at"].nil?
        end
        njob += 1
      end
      puts "Jobber med artifacts: #{ajobs.to_s} og av disse mangler #{aeniljobs.to_s} expiry."
    end
  end
end

def delete_expired_deployments
  deleted=false
  $projects.each do |p|
    id=p["id"]
    $gpath=p["path_with_namespace"]
#    next unless $gpath =~ /^CarPreparation\/hvorerbilen/
    next if $options[:project] and $gpath !~ /#{$options[:project]}/
    rdir="#{$registry_path}/docker/registry/v2/repositories/#{$gpath.downcase}"
    puts "Doing repo path: #{$gpath} project ID: #{id.to_s} rdir #{rdir}"
    if not File.exist?(rdir)
      puts "Rdir is missing."
      next
    elsif not File.exist?("#{rdir}/_manifests")
      puts "Missing _manifests. Skipping this project."
      next
    end

    # Split deployment list per environment.
    # We want to keep n number of successful deployments per environment
    deplist = pageget("/projects/#{id}/deployments")

    if deplist.length < $minimum_deployments
      puts "Project has less than #{$minimum_deployments} deployments (#{deplist.length.to_s}). Skip deleting anything."
      ntags=(Dir.entries("#{rdir}/_manifests/tags").length-2).to_s
      nrevs=(Dir.entries("#{rdir}/_manifests/revisions/sha256").length-2).to_s
      puts "Found #{ntags} tags and #{nrevs} revisions."
      lackdeps=true
    else
      lackdeps=false
    end

    deployments = {}
    deplist.each do |dep|
      did = dep["id"]
      env = dep["environment"]["name"]
      if env == "" or env.nil?
        puts "Empty env?"
        puts "Deployment id=#{did} env=#{env}"
      end
      if deployments[env].nil?
        deployments[env] = []
      end
      deployments[env].push(dep)
    end

    if $options[:debug]
      puts "Data from deployments API:"
      pp deplist
      puts "Deployments per env:"
      pp deployments
    end

    puts "Deployments: " + deplist.length.to_s
    puts "Per env:"
    keeptags = []
    deployments.each_pair do |env,edlist|
      puts "#{env}: #{edlist.length.to_s} deployments."
      ndep = 1
      edlist.sort_by { |k| k["id"] }.reverse.each do |dep|
        did = dep["id"]
        sha = dep["sha"]
        if ndep > $keepimages
          puts "Deployment ID #{did} (nokeep)"
          next
        else
          puts "Deployment ID #{did} (keep)"
        end
        if not dep["deployable"].nil? and not dep["deployable"]["status"].nil?
          depstatus = dep["deployable"]["status"]
        else
          puts "Did not find deployable status? Not keeping or counting this."
        end
        if depstatus == "success"
          keeptags.push(dep["sha"])
          ndep += 1
        else
          puts "Deployment with status #{depstatus}, nothing to keep here?"
        end
      end
    end
    puts "Number of tags to keep: #{keeptags.length.to_s}"
    puts "Tags:"
    pp keeptags

    keepshahs = []
    Dir.entries("#{rdir}/_manifests/tags").each do |tent|
      next if tent =~ /^\.(|\.)$/
      tentfull="#{rdir}/_manifests/tags/#{tent}"
      if keeptags.include?(tent)
        puts "Keep tag entry #{tent}"
        sha = File.read("#{rdir}/_manifests/tags/#{tent}/current/link").chomp.gsub(/^\w+:/, "")
        keepshahs.push(sha)
      else
        puts "Blow tag entry #{tent} .. #{tentfull}"
        if $options[:dryrun]
          puts "Skip deleting tag due to dryrun mode."
        elsif lackdeps
          puts "Skip deleting tag due to too few deployments found."
        else
          deleted=true
          if File.directory?(tentfull)
            puts "Is a directory and can be blown."
            FileUtils.rm_rf(tentfull)
          else
            puts "Is not a directory?"
          end
        end
      end
    end
    # Look through sha256 entries
    Dir.entries("#{rdir}/_manifests/revisions/sha256").each do |sent|
      next if sent =~ /^\.(|\.)$/
      sentfull="#{rdir}/_manifests/revisions/sha256/#{sent}"
      if keepshahs.include?(sent)
        puts "Keep sha265 #{sent}"
      else
        puts "Blow sha265 #{sent} .. #{sentfull}"
        if $options[:dryrun]
          puts "Skip deleting tag due to dryrun mode."
        elsif lackdeps
          puts "Skip deleting tag due to too few deployments found."
        else
          deleted=true
          if File.directory?(sentfull)
            puts "Is a directory and can be blown."
            FileUtils.rm_rf(sentfull)
          else
            puts "Not a directory?"
          end
        end
      end
    end
  end
  if deleted
    puts "Tags or shas were deleted, lets rebuild."
    system("/usr/bin/gitlab-ctl registry-garbage-collect")
  end
end

$headers = {
	"Private-Token" => token,
	"Accept" => "*/*",
	"Content-Type" => "application/json",
}

$projects = pageget("/projects")
puts "Number of projects: #{$projects.length.to_s}"

if $options[:nojobs]
  puts "Skip handling jobs and artifacts."
else
  puts "Do jobs and artifacts now."
  delete_artifact_jobs
end
if $options[:nodeployments]
  puts "Skip handling deployments."
else
  puts "Do deployments now."
  delete_expired_deployments
end



