import Config

config_name = System.get_env("CONFIG", "default")
config_file = "#{config_name}.config.exs"

[File.cwd!, "config", config_file]
|> Path.join()
|> File.exists?()
|> case do
  true -> import_config(config_file)
  false -> :noop
end
