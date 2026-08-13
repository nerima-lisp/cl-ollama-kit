#.(progn (in-package :ollama-kit) nil)

(defun %validate-web-query (query)
  (unless (and (stringp query) (plusp (length query)))
    (error 'ollama-argument-error
           :message "Web search queries must be non-empty strings."))
  query)

(defun %validate-web-max-results (max-results)
  (unless (and (integerp max-results)
               (<= 1 max-results 10))
    (error 'ollama-argument-error
           :message "Web search max-results must be an integer from 1 through 10."))
  max-results)

(defun %validate-web-url (url)
  (unless (and (stringp url) (plusp (length url)))
    (error 'ollama-argument-error
           :message "Web fetch URLs must be non-empty strings."))
  url)

(defun web-search (client query &key (max-results +json-unspecified+)
                                      (timeout +timeout-unspecified+)
                                      headers)
  "Search the web through Ollama's `/web_search` endpoint.

The endpoint is provided by Ollama Cloud. Configure CLIENT with the cloud
`/api` base URL and an API key when using the hosted service."
  (%validate-web-query query)
  (unless (eq max-results +json-unspecified+)
    (%validate-web-max-results max-results))
  (%request-json-value
   client :post "/web_search"
   :body (if (eq max-results +json-unspecified+)
             (json-object "query" query)
             (json-object "query" query "max_results" max-results))
   :timeout timeout
   :headers headers))

(defun web-fetch (client url
                  &key (timeout +timeout-unspecified+) headers)
  "Fetch a web page through Ollama's `/web_fetch` endpoint.

The endpoint is provided by Ollama Cloud. Configure CLIENT with the cloud
`/api` base URL and an API key when using the hosted service."
  (%validate-web-url url)
  (%request-json-value client :post "/web_fetch"
                       :body (json-object "url" url)
                       :timeout timeout
                       :headers headers))
