// Package middleware provides HTTP middleware for the gateway service.
package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog/log"
	"github.com/vectorflow/gateway/internal/config"
)

// Claims represents the JWT claims structure.
type Claims struct {
	UserID string   `json:"user_id"`
	Email  string   `json:"email"`
	Role   string   `json:"role"`
	Scopes []string `json:"scopes,omitempty"`
	jwt.RegisteredClaims
}

// ContextKey is the key used to store user info in context.
const ContextKey = "user"

// JWTAuth creates a JWT authentication middleware.
func JWTAuth(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip auth if disabled
		if !cfg.Auth.Enabled {
			c.Next()
			return
		}

		// Extract token from header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			// Try API key as fallback
			apiKey := c.GetHeader(cfg.Auth.APIKeyHeader)
			if apiKey != "" && isValidAPIKey(apiKey, cfg.Auth.APIKeys) {
				// API key authentication successful
				c.Set(ContextKey, &Claims{
					UserID: "api-key-user",
					Role:   "service",
					Scopes: []string{"read", "write"},
				})
				c.Next()
				return
			}

			abortUnauthorized(c, "Missing authorization header")
			return
		}

		// Parse Bearer token
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			abortUnauthorized(c, "Invalid authorization header format")
			return
		}

		tokenString := parts[1]

		// Parse and validate JWT
		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			// Validate signing method
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(cfg.Auth.JWTSecret), nil
		})

		if err != nil {
			log.Debug().Err(err).Msg("JWT validation failed")
			abortUnauthorized(c, "Invalid or expired token")
			return
		}

		if !token.Valid {
			abortUnauthorized(c, "Invalid token")
			return
		}

		// Check expiration
		if claims.ExpiresAt != nil && claims.ExpiresAt.Time.Before(time.Now()) {
			abortUnauthorized(c, "Token expired")
			return
		}

		// Store claims in context
		c.Set(ContextKey, claims)

		log.Debug().
			Str("user_id", claims.UserID).
			Str("role", claims.Role).
			Msg("Authenticated request")

		c.Next()
	}
}

// RequireRole creates middleware that requires a specific role.
func RequireRole(roles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, exists := c.Get(ContextKey)
		if !exists {
			abortForbidden(c, "No authentication context")
			return
		}

		userClaims, ok := claims.(*Claims)
		if !ok {
			abortForbidden(c, "Invalid authentication context")
			return
		}

		// Check if user has required role
		for _, role := range roles {
			if userClaims.Role == role {
				c.Next()
				return
			}
		}

		abortForbidden(c, "Insufficient permissions")
	}
}

// RequireScope creates middleware that requires specific scopes.
func RequireScope(requiredScopes ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, exists := c.Get(ContextKey)
		if !exists {
			abortForbidden(c, "No authentication context")
			return
		}

		userClaims, ok := claims.(*Claims)
		if !ok {
			abortForbidden(c, "Invalid authentication context")
			return
		}

		// Check if user has all required scopes
		for _, required := range requiredScopes {
			found := false
			for _, scope := range userClaims.Scopes {
				if scope == required {
					found = true
					break
				}
			}
			if !found {
				abortForbidden(c, "Missing required scope: "+required)
				return
			}
		}

		c.Next()
	}
}

// OptionalAuth creates middleware that extracts JWT if present but doesn't require it.
func OptionalAuth(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Next()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			c.Next()
			return
		}

		tokenString := parts[1]
		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(cfg.Auth.JWTSecret), nil
		})

		if err == nil && token.Valid {
			c.Set(ContextKey, claims)
		}

		c.Next()
	}
}

// GetClaims retrieves the JWT claims from the context.
func GetClaims(c *gin.Context) (*Claims, bool) {
	claims, exists := c.Get(ContextKey)
	if !exists {
		return nil, false
	}
	userClaims, ok := claims.(*Claims)
	return userClaims, ok
}

// isValidAPIKey checks if the provided API key is valid.
func isValidAPIKey(key string, validKeys []string) bool {
	for _, k := range validKeys {
		if k == key {
			return true
		}
	}
	return false
}

func abortUnauthorized(c *gin.Context, message string) {
	c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
		"error":     "Unauthorized",
		"message":   message,
		"timestamp": time.Now().UTC(),
	})
}

func abortForbidden(c *gin.Context, message string) {
	c.AbortWithStatusJSON(http.StatusForbidden, gin.H{
		"error":     "Forbidden",
		"message":   message,
		"timestamp": time.Now().UTC(),
	})
}
