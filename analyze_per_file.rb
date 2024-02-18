require 'yaml'

KINDS = [:examples, :errors, :failures, :tagged, :time]

DETAILS = ARGV.delete('--details')
USE_MRI_TOTALS = ARGV.delete('--mri-totals')
HTML = ARGV.delete('--html')

longest_group = "total_no_capi".size

processed = {}
ARGV.each { |results_file|
  results_file =~ /^(\w+)\/(.+)\.yml$/ or raise results_file
  ruby, group = $1, $2
  data = YAML.load_file(results_file, symbolize_names: true)
  processed[ruby] ||= {}
  processed[ruby][group] = data
}

mri_summary = processed.find { |ruby,| ruby.start_with?('ruby') }[1]

# Fix up data
processed.each_pair do |ruby, summary|
  mri_summary.each_pair do |group,|
    unless summary.include?(group)
      STDERR.puts "#{ruby} has no #{group} specs"
      summary[group] = KINDS.map { |kind| [kind, 0] }.to_h
    end
  end

  summary.each_pair do |group, totals|
    if totals[:examples] == 0
      STDERR.puts "Correcting examples for #{group} for #{ruby}"
      totals[:examples] = mri_summary[group][:examples]
      totals[:errors] = totals[:examples]
    end
  end
end

if USE_MRI_TOTALS
  processed.each_pair do |ruby, summary|
    summary.each_pair do |group, totals|
      mri = mri_summary[group]
      diff = mri[:examples] - totals[:examples]
      if diff > 0
        totals[:examples] += diff
        totals[:errors] += diff
      elsif diff < 0
        STDERR.puts "More examples for #{group} on #{ruby}: #{totals[:examples]} vs #{mri[:examples]}"
        # raise totals.inspect
      end
    end
  end
end

examples_per_group = Hash.new { |h,k| h[k] = [] }
processed.each_pair do |ruby, summary|
  summary.each_pair do |group, totals|
    examples_per_group[group] << totals[:examples]
  end
end
same_number_of_specs = examples_per_group.to_h { |group, examples| [group, examples.uniq.size == 1] }

# Compute totals
processed.each_pair do |ruby, summary|
  summary["total"] = KINDS.map { |kind| [kind, summary.sum { |_, totals| totals[kind] }] }.to_h

  summary_no_capi = summary.reject { |key, _| key == 'capi' or key == 'total' }.to_h
  summary["total_no_capi"] = KINDS.map { |kind| [kind, summary_no_capi.sum { |_, totals| totals[kind] }] }.to_h

  summary.each_value do |totals|
    totals[:passing] = totals[:examples] - totals[:errors] - totals[:failures] - totals[:tagged]
  end
end

if HTML
  # https://medium.com/@pppped/how-to-code-a-responsive-circular-percentage-chart-with-svg-and-css-3632f8cd7705
  circle = -> percents {
    text = percents == 100.0 ? "100" : "%.1f" % percents
    <<-SVG
    <svg viewBox="0 0 36 36" class="circular-chart">
      <path class="circle-bg"
        d="M18 2.0845
          a 15.9155 15.9155 0 0 1 0 31.831
          a 15.9155 15.9155 0 0 1 0 -31.831"/>
      <path class="circle"
       stroke-dasharray="#{percents}, 100"
       d="M18 2.0845
          a 15.9155 15.9155 0 0 1 0 31.831
          a 15.9155 15.9155 0 0 1 0 -31.831"/>
      <text x="18" y="20.35" class="percentage">#{text}%</text>
    </svg>
    SVG
  }

  puts <<~HTML
  <html>
  <head>
    <title>Passing Specs per Ruby Implementation</title>

    <link rel="stylesheet" href="https://eregon.me/blog/assets/main.css?v=1">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Libre+Baskerville:400,400i,700">
    <link rel="stylesheet" href="https://eregon.me/blog/assets/custom.css?v=1">
    <link rel="stylesheet" href="https://eregon.me/blog/assets/syntax.css?v=1">
    <link rel="stylesheet" href="https://eregon.me/blog/assets/table.css?v=1">
    <link rel="stylesheet" href="https://eregon.me/blog/assets/circle.css?v=1">
  </head>
  <body><main><div class="post">

  <h1 class="post-title">Passing Specs per Ruby Implementation</h1>
  <p>
    This page shows the number of passing <a href="https://github.com/ruby/spec">ruby/spec</a> specs per Ruby implementation.
    This page is updated daily and automatically with GitHub Actions on <a href="https://github.com/eregon/rubyspec-stats">this repository</a>.
  </p>
  <p>
    Specs excluded by a Ruby implementation (via tags) are not run, as those may cause a fatal error and abort the process, and also they are not run in that implementation's CI.
    Specs are run on a Ruby implementation with no extra options, i.e., with the default behavior a user would see.
    The only exception is using <code>--dev</code> on JRuby so it runs specs slightly faster.
    More details are available in this related <a href="https://eregon.me/blog/2020/06/27/ruby-spec-compatibility-report.html">blog post</a>.
  </p>
  <p>
    More Ruby implementations are welcome via PRs.
    See <a href="https://github.com/eregon/rubyspec-stats/blob/master/.github/workflows/ci.yml">this workflow</a> for how it works.
  </p>

  <table style="width: 100%">
  HTML
  puts "<colgroup>"
  group_width = 16
  puts %Q{<col span="1" style="width: #{group_width}%;">}
  processed.each_key do
    puts %Q{<col span="1" style="width: #{((100 - group_width) / processed.size)}%">}
  end
  puts "</colgroup>"
  puts "<thead>"

  puts "<th>Group</th>"
  processed.each_key do |ruby|
    # ruby_name = ruby.sub(/-/, ' ').sub(/^ruby/, 'cruby').capitalize.sub('ruby', 'Ruby')
    ruby_name = ruby.sub(/-/, ' ').sub(/^ruby/, 'cruby').split.first.capitalize.sub('ruby', 'Ruby')
    if ruby_name == 'CRuby'
      ruby_version_file = "#{ruby}/RUBY_VERSION"
      major_minor = File.read(ruby_version_file)[/^\d+\.\d+/]
      ruby_name = "CRuby #{major_minor}"
    else
      ruby_name = "#{ruby_name} dev"
    end
    puts %Q{<th style="text-align: center">#{ruby_name}</th>}
  end
  puts "</thead>"

  groups = mri_summary.keys.sort_by { |group|
    %w[command_line language core library security total_no_capi capi total].index(group) || raise(group)
  }

  puts "<tbody>"
  puts '<tr>'
  puts '<td>RUBY_VERSION</td>'
  processed.each_key do |ruby|
    ruby_version_file = "#{ruby}/RUBY_VERSION"
    ruby_version = File.exist?(ruby_version_file) ? File.read(ruby_version_file) : '?'
    puts %Q{<td style="text-align: center">#{ruby_version}</th>}
  end
  puts '</tr>'

  groups.each do |group|
    case group
    when 'total'
      group_name = '<b>TOTAL</b>'
    when 'total_no_capi'
      group_name = '<b>TOTAL without C-API specs</b>'
    else
      group_name = group.gsub('_', '-').capitalize
      group_name = group_name.sub('Capi', 'C-API').sub('Library', 'Standard Library').sub('Core', 'Core Library')
      link = group == 'capi' ? 'optional/capi' : group
      group_name = %Q{<a href="https://github.com/ruby/spec/tree/master/#{link}">#{group_name}</a>}
      # group_name += " specs"
    end
    puts group.start_with?('total') ? '<tr style="border-top: 2px solid black">' : '<tr>'
    if same_number_of_specs[group]
      puts "<td>#{group_name}<br/>\n#{mri_summary[group][:examples]} specs</td>"
    else
      puts "<td>#{group_name}</td>"
    end
    processed.each_pair do |ruby, summary|
      totals = summary[group]
      ratio = totals[:passing].to_f / totals[:examples]
      puts '<td style="text-align: center">'
      puts circle[ratio * 100]
      if group.start_with?('total')
        puts %Q{<span style="font-size: 95%">#{totals[:passing]} passing<br/>in #{totals[:time].to_i.divmod(60).join('min ')}s</span>}
      else
        unless same_number_of_specs[group]
          puts %Q{<span style="font-size: 95%">of #{totals[:examples]} specs</span>}
        end
      end
      puts "</td>"
    end
    puts "</tr>"
  end
  puts <<~HTML
  </tbody>
  </table>
  </div></main>
  <footer><span>© 2022 Benoit Daloze.</span></footer>
  </body>
  HTML
else
  processed.each_pair do |ruby, summary|
    puts nil, ruby

    if DETAILS
      summary.each_pair do |group, totals|
        puts "#{group.ljust(longest_group)} #{totals}"
      end
      puts
    end

    summary.each_pair do |group, totals|
      f = "%5d"
      ratio = totals[:passing].to_f / totals[:examples]
      puts "#{group.ljust(longest_group)} #{f % totals[:passing]}/#{f % totals[:examples]} = #{"%6.2f" % (ratio * 100)}%"
    end
  end
end
