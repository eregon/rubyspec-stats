require 'bundler/setup'
require 'octokit'
require 'yaml'

client = Octokit::Client.new
CLIENT = client

# Using contributors_stats() and not contributors() because
# only the former matches https://github.com/.../.../graphs/contributors
def contributors(repo)
  cache = "#{File.basename(repo)}_contributors.yml"
  if File.exist?(cache)
    YAML.load_file(cache)
  else
    data = CLIENT.contributors_stats(repo).reverse.to_h { [it[:author][:login], it[:total]] }
    raise repo unless data.size == 100 or repo == 'natalie-lang/natalie'
    File.write cache, YAML.dump(data)
    data
  end
end

per_implementation_contributors = {
  cruby: contributors('ruby/ruby'),
  rubinius: contributors('rubinius/rubinius'),
  jruby: contributors('jruby/jruby'),
  truffleruby: contributors('oracle/truffleruby'),
  natalie: contributors('natalie-lang/natalie'),
}

implementations = per_implementation_contributors.keys + [:external]

contributors = contributors('ruby/spec')

mapping = contributors.map { |author,commits| author }.to_h { |author|
  commits_per_impl = per_implementation_contributors.filter_map { [_1, _2[author]] if _2[author] }
  # p [author, *commits_per_impl]
  impl, commits = commits_per_impl.max_by(&:last)
  if impl and commits >= 10
    [author, impl]
  else
    [author, :external]
  end
}
pp mapping

total_commits = contributors.values.sum
puts "#{total_commits} commits from the top #{contributors.size} contributors"

cache = 'per_year.yml'
if File.exist?(cache)
  per_year = YAML.load_file(cache)
else
  per_year = Hash.new { |h,year| h[year] = Hash.new(0) }

  client.contributors_stats('ruby/spec').each do |contributor|
    author = contributor[:author][:login]

    raise author unless contributor[:total] == contributor[:weeks].sum { it[:c] }

    contributor[:weeks].each { |contrib|
      commits = contrib[:c]
      if commits > 0
        year = Time.at(contrib[:w]).utc.year
        per_year[year][author] += commits
      end
    }
  end
  per_year = per_year.sort_by(&:first).to_h
  per_year.transform_values! { |author_commits|
    author_commits.sort_by(&:last).reverse.to_h
  }

  File.write cache, YAML.dump(per_year)
end

pp per_year

per_year_per_impl = per_year.to_h { |year, contribs|
  stats = implementations.to_h { [it, 0] }
  contribs.each { |author, commits|
    impl = mapping.fetch(author)
    if impl == :truffleruby and year < 2014
      impl = { "eregon" => :external, "timfel" => :jruby }.fetch(author)
      puts "Changed truffleruby to #{impl} for #{author} in #{year} for #{commits} commits"
    end
    stats[impl] += commits
  }
  [year, stats]
}

pp per_year_per_impl
File.write 'per_year_per_impl.yml', YAML.dump(per_year_per_impl)
