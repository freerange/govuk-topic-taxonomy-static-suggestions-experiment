require 'rake/clean'
require 'csv'
require 'nokogiri'
require 'json'
require 'ruby_llm'
require 'sqlite3'
require 'sqlite_vec'
require 'erb'

RubyLLM.configure do |config|
  config.openrouter_api_key = ENV['OPENROUTER_API_KEY']
end

directory 'extract'
directory 'db'
directory 'transform/clean'
directory 'transform/embeddings'
directory 'transform/similarities'
directory 'public'

desc 'Prepare input CSV file by querying content store base'
file 'extract/raw.csv' => 'extract' do
  query_file = File.join(File.dirname(__FILE__), 'query.sql')
  output = File.join(File.dirname(__FILE__), 'extract', 'raw.csv')

  sh "govuk-docker up -d content-store-lite"
  sh "docker exec -i govuk-docker-content-store-lite-1 rails db < #{query_file} > #{output}"
  sh "govuk-docker down content-store-lite"
end

def raw_data
  return [] if !File.exist?('extract/raw.csv')

  @raw ||= CSV.read('extract/raw.csv', headers: true)
end

def raw_data_ids
  raw_data.map { |row| row['id'] }
end

def strip_tags(s)
  Nokogiri.HTML(s).text.gsub(/\\n\s*/, " ")
end

def metadata_for(id)
  JSON.load_file("transform/clean/#{id}.json")
end

raw_data_ids.each do |id|
  desc "Prepare file transform/clean/#{id}.json"
  file "transform/clean/#{id}.json" => ['transform/clean', 'extract/raw.csv'] do |f|
    data = raw_data.find {|r| r['id'] == id}

    taxons = JSON.parse(data['taxons'])
    cleaned_taxons = taxons.map { |t| t.select { |key, _| ['title', 'base_path'].include?(key) } }

    File.write(
      f.name,
      JSON.pretty_generate(
        {
          title: data['title'],
          body: strip_tags(data['body']),
          base_path: data['base_path'],
          taxons: cleaned_taxons
        }))
  end
end

desc 'Regenerate all files in transform/clean'
task :transform_clean => raw_data_ids.map { |id| "transform/clean/#{id}.json" }

raw_data_ids.each do |id|
  desc "Prepare file transform/embeddings/#{id}.json"
  file "transform/embeddings/#{id}.json" => ['transform/embeddings', "transform/clean/#{id}.json"] do |f|
    puts "Generating #{f.name}"

    input_json = JSON.load_file("transform/clean/#{id}.json")
    text_to_embed = [input_json['title'], input_json['body']].join(' ')

    embedding = RubyLLM.embed(
      text_to_embed,
      provider: 'openrouter',
      model: 'qwen/qwen3-embedding-4b',
      assume_model_exists: true
    )

    File.write(
      f.name,
      JSON.pretty_generate(
        {
          title: input_json['title'],
          vector: embedding.vectors
        }))
  end
end

desc 'Regenerate all files in transform/embeddings'
task :transform_embeddings => raw_data_ids.map { |id| "transform/embeddings/#{id}.json" }

file 'db/similarity.db' => ['db', raw_data_ids.map { |id| "transform/embeddings/#{id}.json" }].flatten  do
  db = SQLite3::Database.new('db/similarity.db')
  db.enable_load_extension(true)
  SqliteVec.load(db)
  db.enable_load_extension(false)
  db.execute("CREATE VIRTUAL TABLE vec_items USING vec0(id TEXT PRIMARY KEY, embedding float[2560])")

  raw_data_ids.each do |id|
    input_json = JSON.load_file("transform/embeddings/#{id}.json")
    vector = input_json['vector']

    db.execute("INSERT INTO vec_items(id, embedding) VALUES (?, ?)", [id, vector.pack("f*")])
  end
end

raw_data_ids.each do |id|
  desc "Prepare file transform/similarities/#{id}.json"
  file "transform/similarities/#{id}.json" => ['transform/similarities', "transform/embeddings/#{id}.json", 'db/similarity.db'] do |f|
    puts "Generating #{f.name}"

    input_json = JSON.load_file("transform/embeddings/#{id}.json")

    query = input_json['vector']

    db = SQLite3::Database.new('db/similarity.db')
    db.enable_load_extension(true)
    SqliteVec.load(db)
    db.enable_load_extension(false)

    rows = db.execute(<<-SQL, [query.pack("f*")])
      SELECT
        id
      FROM vec_items
      WHERE embedding MATCH ?
      ORDER BY distance
      LIMIT 6
    SQL

    File.write(
      f.name,
      JSON.pretty_generate(
        {
          title: input_json['title'],
          similar_document_ids: rows[1..].flatten
        }))
  end
end

desc 'Regenerate all files in transform/similarities'
task :transform_similarities => raw_data_ids.map { |id| "transform/similarities/#{id}.json" }

raw_data_ids.each do |id|
  desc "Prepare file public/#{id}.html"
  file "public/#{id}.html" => ['public', "transform/similarities/#{id}.json"] do |f|
    puts "Generating #{f.name}"

    input_json = JSON.load_file("transform/similarities/#{id}.json")
    title = input_json['title']
    url = 'https://www.gov.uk' + metadata_for(id)['base_path']
    similar_documents = input_json['similar_document_ids'].map { |id| [id, metadata_for(id)['title']] }

    template = <<-TEMPLATE
      <h1><a href="<%= url %>"><%= title %></a></h1>
      <ol>
      <% similar_documents.each do |id, title| %>
        <li><a href="<%= id %>.html"><%= title %></a></li>
      <% end %>
      </ol>
    TEMPLATE

    erb = ERB.new(template)
    html = erb.result(binding)

    File.write(f.name, html)
  end
end

desc 'Regenerate all files in public'
task :public_files => raw_data_ids.map { |id| "public/#{id}.html" }

desc "Prepare file public/index.html"
file 'public/index.html' => :public_files do |f|
  puts "Generating #{f.name}"

  documents = raw_data_ids.map { |id| [id, metadata_for(id)['title']] }

  template = <<-TEMPLATE
    <h1>Index</h1>
    <ol>
    <% documents.each do |id, title| %>
      <li><a href="<%= id %>.html"><%= title %></a></li>
    <% end %>
    </ol>
  TEMPLATE

  erb = ERB.new(template)
  html = erb.result(binding)
  File.write(f.name, html)
end

task :setup => ['extract/raw.csv']

task :default do
  Rake::Task['setup'].invoke
  exec('rake', 'public/index.html')
end

CLOBBER.include('extract', 'transform', 'public', 'db')
