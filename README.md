This repo contains code in support of a prototype built in 2026. The purpose of the prototype was to develop a method of suggesting appropriate topic taxonomy tags for existing and new documents published on GOV.UK.

Documents published on GOV.UK can have one or more topics attached to them. Topics (also referred to as "taxons") have a parent, and all the taxons taken together form a tree known as the [topic taxonomy](https://docs.publishing.service.gov.uk/manual/taxonomy.html).

This taxonomy is used in a number of ways, for example:
 - As a [filter in some search pages](https://www.gov.uk/search/news-and-communications)
 - To create [topic index pages](https://www.gov.uk/government/national-security)
 - In the [search-api](https://docs.publishing.service.gov.uk/repos/search-api.html)

These use cases benefit from documents being tagged with a) the most specific (deepest in the tree) taxon possible and b) more than one taxon.

This prototype shows one possible method of suggesting appropriate topic taxons namely using the topics similar documents are tagged with. Features based on this method could be used in publishing applications such as [Whitehall](https://docs.publishing.service.gov.uk/repos/whitehall.html) or in tagging-specific applications such as [ContentTagger](https://docs.publishing.service.gov.uk/repos/content-tagger.html).

## Running the prototype

This prototype uses a `Rake` file to generate some static HTML pages showing the suggested topic taxonomy tags for a selection of documents. The generated files are commited to this repository so can be viewed without installing any dependencies. From a clone of this repo run

``` shell
open public/index.html
```

## Rebuild the recommendations

Ensure you are running the version of Ruby in `.ruby-version`.

This prototype also assumes you are:
- running `govuk-docker`
- are able to start a `content-store-lite` container and
- have a [recent replica of the content store database](https://github.com/alphagov/govuk-docker/blob/main/docs/how-tos.md#how-to-replicate-data-locally).

Install the dependencies with

``` shell
bundle install
```

Obtain and set the API key for an [OpenRouter account](https://openrouter.ai/)

``` shell
export OPENROUTER_API_KEY='...'
```

Then remove all existing generated files using

``` shell
rake clobber
```

Finally regenerate the index file using

``` shell
rake public/index.html
```

Passing the `-n -j<number>` options to rake can speed up the process by running tasks in parallel. Consult the Rake docs to choose a suitable number for `-j`.

## Overview of the recommendation pipeline

The core of the topic tag recommendation algorithm is as follows:
- For each document
  - Convert its content to a vector of embeddings
  - Load the embeddings into a vector database
- Then for each document
  - Find the 5 most similar documents by querying the vector database
  - Recommend the topic tags thees documents were tagged with

This is performed for every document in the dataset and a HTML page is generated for each document. This is achieved with a series of dependent rake tasks:

### Extract (`rake extract/raw.csv`)

Queries the Content Store database via `govuk-docker` to get GOV.UK pages with their titles, bodies, base paths, and associated taxons. The `query.sql` file defines the SQL query.

### Transform - Clean (`rake transform_clean`)

This task strips HTML tags from the body of each document, and truncates it to 500 words.

### Transform - Embeddings (`rake transform_embeddings`)

Generates vector embeddings for each document using an the `qwen/qwen3-embedding-4b` model. The title and body text are concatenated before embedding.

### Create vector database (`rake db/similarity.db`)

Loads the embeddings for each document into an SQLite database. This database uses the `sqlite-vec` extension to make vector similarity searches more efficient.

### Transform - Similarities (`rake transform_similarities`)

Finds the 5 most similar documents for each document by querying the vector database.

### Generate HTML (`rake public/index.html`)

Creates an index page and pages for each document. The pages have a link to the source document, the document's current taxons, the 5 similar documents and suggested taxons based on what those similar documents are tagged with.

## Limitations

The prototype as it is presented has a number of limitations that would need to be addressed in order to put a feature using this approach into production:

- To reduce the amount of computation it is based on a static snapshot of Whitehall documents published since the start of 2025.
- We have made no further attempts to curate the documents used to build the recommendation dataset. Better results may be obtained by ensuring that every topic taxon is well- and equally-represented by example documents.
- To keep within the context window of the [embedding model used](https://openrouter.ai/qwen/qwen3-embedding-4b) the input text is truncated to 500 words. We also ignore any HTML or PDF attachments for a given document. It may be possible to use an LLM or other summarisation technique to reduce the text to be embedded to a fixed token length.
- We haven't attempted to tune the results. To do this we would need an objective measure of the quality of the suggestions. We considered using published documents as a ground truth and measuring our prediction acccuracy using a [top-N metric](https://stats.stackexchange.com/questions/95391/what-is-the-definition-of-top-n-accuracy) but there are many other approaches[1].
- In production we'd need to be adding new documents (and by extension any new topic taxons) to the vector database.

## References

[1] Eva Zangerle and Christine Bauer. 2022. Evaluating Recommender Systems: Survey and Framework. ACM Comput. Surv. 55, 8, Article 170 (August 2023), 38 pages. https://doi.org/10.1145/3556536
