# ExMicrosoftAzureStorage

An early prototype of an SDK to interact with Microsoft Azure Storage.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_microsoft_azure_storage` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_microsoft_azure_storage, app: false, github: "chgeuer/ex_microsoft_azure_storage", ref: "master"}
    
    # Optional dependency, you can also add your own json_library dependency
    # and config with `config :ex_microsoft_azure_storage, json_library, YOUR_JSON_LIBRARY`
    {:jason, "~> 1.1"}
  ]
end
```
