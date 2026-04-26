// Package config provides configuration management for the gateway service.
package config

import (
	"time"

	"github.com/spf13/viper"
)

// Config holds all configuration for the gateway service.
type Config struct {
	Server   ServerConfig
	Services ServicesConfig
	Auth     AuthConfig
	Logging  LoggingConfig
}

// ServerConfig holds server-specific configuration.
type ServerConfig struct {
	Host         string        `mapstructure:"host"`
	Port         int           `mapstructure:"port"`
	ReadTimeout  time.Duration `mapstructure:"read_timeout"`
	WriteTimeout time.Duration `mapstructure:"write_timeout"`
	IdleTimeout  time.Duration `mapstructure:"idle_timeout"`
	Environment  string        `mapstructure:"environment"`
}

// ServicesConfig holds URLs for downstream services.
type ServicesConfig struct {
	WorkerURL    string        `mapstructure:"worker_url"`
	InferenceURL string        `mapstructure:"inference_url"`
	Timeout      time.Duration `mapstructure:"timeout"`
}

// AuthConfig holds authentication configuration.
type AuthConfig struct {
	Enabled   bool     `mapstructure:"enabled"`
	JWTSecret string   `mapstructure:"jwt_secret"`
	APIKeys   []string `mapstructure:"api_keys"`
}

// LoggingConfig holds logging configuration.
type LoggingConfig struct {
	Level  string `mapstructure:"level"`
	Format string `mapstructure:"format"`
}

// Load reads configuration from environment variables and config files.
func Load() (*Config, error) {
	v := viper.New()

	// Set defaults
	v.SetDefault("server.host", "0.0.0.0")
	v.SetDefault("server.port", 8080)
	v.SetDefault("server.read_timeout", "30s")
	v.SetDefault("server.write_timeout", "30s")
	v.SetDefault("server.idle_timeout", "120s")
	v.SetDefault("server.environment", "development")

	v.SetDefault("services.worker_url", "http://localhost:8081")
	v.SetDefault("services.inference_url", "http://localhost:8082")
	v.SetDefault("services.timeout", "30s")

	v.SetDefault("auth.enabled", false)
	v.SetDefault("auth.jwt_secret", "")
	v.SetDefault("auth.api_keys", []string{})

	v.SetDefault("logging.level", "info")
	v.SetDefault("logging.format", "json")

	// Bind environment variables
	v.SetEnvPrefix("GATEWAY")
	v.AutomaticEnv()

	// Map environment variables
	v.BindEnv("server.host", "GATEWAY_HOST")
	v.BindEnv("server.port", "GO_GATEWAY_PORT")
	v.BindEnv("server.environment", "ENVIRONMENT")
	v.BindEnv("services.worker_url", "WORKER_SERVICE_URL")
	v.BindEnv("services.inference_url", "INFERENCE_SERVICE_URL")
	v.BindEnv("auth.jwt_secret", "JWT_SECRET")
	v.BindEnv("logging.level", "LOG_LEVEL")

	// Read config file if exists
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath(".")
	v.AddConfigPath("./config")
	v.AddConfigPath("/etc/vectorflow/")

	if err := v.ReadInConfig(); err != nil {
		// Config file not found is okay
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, err
		}
	}

	var cfg Config
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// IsProduction returns true if running in production environment.
func (c *Config) IsProduction() bool {
	return c.Server.Environment == "production"
}
