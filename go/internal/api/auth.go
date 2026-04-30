// Package api provides HTTP handlers for the gateway service.
package api

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog/log"
	"github.com/vectorflow/gateway/internal/config"
	"github.com/vectorflow/gateway/internal/middleware"
	"golang.org/x/crypto/bcrypt"
)

// AuthHandler handles authentication-related requests.
type AuthHandler struct {
	cfg   *config.Config
	users map[string]*User // In-memory user store (replace with DB in production)
}

// User represents a user in the system.
type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Role         string    `json:"role"`
	Scopes       []string  `json:"scopes"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// ----- Request/Response Models -----

// RegisterRequest represents a user registration request.
type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8,max=128"`
	Name     string `json:"name" binding:"omitempty,max=100"`
}

// LoginRequest represents a login request.
type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

// TokenResponse represents a successful authentication response.
type TokenResponse struct {
	AccessToken  string    `json:"access_token"`
	TokenType    string    `json:"token_type"`
	ExpiresIn    int64     `json:"expires_in"`
	ExpiresAt    time.Time `json:"expires_at"`
	RefreshToken string    `json:"refresh_token,omitempty"`
	User         UserInfo  `json:"user"`
}

// UserInfo represents public user information.
type UserInfo struct {
	ID     string   `json:"id"`
	Email  string   `json:"email"`
	Role   string   `json:"role"`
	Scopes []string `json:"scopes"`
}

// RefreshRequest represents a token refresh request.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// NewAuthHandler creates a new AuthHandler instance.
func NewAuthHandler(cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		cfg:   cfg,
		users: make(map[string]*User),
	}
}

// ----- Auth Endpoints -----

// Register handles user registration.
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "ValidationError",
			"message": err.Error(),
		})
		return
	}

	// Check if user exists
	if _, exists := h.users[req.Email]; exists {
		c.JSON(http.StatusConflict, gin.H{
			"error":   "UserExists",
			"message": "A user with this email already exists",
		})
		return
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		log.Error().Err(err).Msg("Failed to hash password")
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "InternalError",
			"message": "Failed to process registration",
		})
		return
	}

	// Create user
	userID := generateID()
	user := &User{
		ID:           userID,
		Email:        req.Email,
		PasswordHash: string(hashedPassword),
		Role:         "user", // Default role
		Scopes:       []string{"read", "write"},
		CreatedAt:    time.Now().UTC(),
		UpdatedAt:    time.Now().UTC(),
	}

	h.users[req.Email] = user

	// Generate token
	token, expiresAt, err := h.generateToken(user)
	if err != nil {
		log.Error().Err(err).Msg("Failed to generate token")
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "InternalError",
			"message": "Failed to generate token",
		})
		return
	}

	log.Info().
		Str("user_id", userID).
		Str("email", req.Email).
		Msg("User registered")

	c.JSON(http.StatusCreated, TokenResponse{
		AccessToken: token,
		TokenType:   "Bearer",
		ExpiresIn:   int64(h.cfg.Auth.TokenExpiry.Seconds()),
		ExpiresAt:   expiresAt,
		User: UserInfo{
			ID:     user.ID,
			Email:  user.Email,
			Role:   user.Role,
			Scopes: user.Scopes,
		},
	})
}

// Login handles user login.
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "ValidationError",
			"message": err.Error(),
		})
		return
	}

	// Find user
	user, exists := h.users[req.Email]
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "InvalidCredentials",
			"message": "Invalid email or password",
		})
		return
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "InvalidCredentials",
			"message": "Invalid email or password",
		})
		return
	}

	// Generate token
	token, expiresAt, err := h.generateToken(user)
	if err != nil {
		log.Error().Err(err).Msg("Failed to generate token")
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "InternalError",
			"message": "Failed to generate token",
		})
		return
	}

	// Generate refresh token
	refreshToken, err := h.generateRefreshToken(user)
	if err != nil {
		log.Error().Err(err).Msg("Failed to generate refresh token")
		// Continue without refresh token
	}

	log.Info().
		Str("user_id", user.ID).
		Str("email", user.Email).
		Msg("User logged in")

	c.JSON(http.StatusOK, TokenResponse{
		AccessToken:  token,
		TokenType:    "Bearer",
		ExpiresIn:    int64(h.cfg.Auth.TokenExpiry.Seconds()),
		ExpiresAt:    expiresAt,
		RefreshToken: refreshToken,
		User: UserInfo{
			ID:     user.ID,
			Email:  user.Email,
			Role:   user.Role,
			Scopes: user.Scopes,
		},
	})
}

// Refresh handles token refresh.
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "ValidationError",
			"message": err.Error(),
		})
		return
	}

	// Parse refresh token
	claims := &middleware.Claims{}
	token, err := jwt.ParseWithClaims(req.RefreshToken, claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(h.cfg.Auth.JWTSecret + "-refresh"), nil
	})

	if err != nil || !token.Valid {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "InvalidToken",
			"message": "Invalid or expired refresh token",
		})
		return
	}

	// Find user
	var user *User
	for _, u := range h.users {
		if u.ID == claims.UserID {
			user = u
			break
		}
	}

	if user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "UserNotFound",
			"message": "User not found",
		})
		return
	}

	// Generate new tokens
	newToken, expiresAt, err := h.generateToken(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "InternalError",
			"message": "Failed to generate token",
		})
		return
	}

	newRefreshToken, _ := h.generateRefreshToken(user)

	c.JSON(http.StatusOK, TokenResponse{
		AccessToken:  newToken,
		TokenType:    "Bearer",
		ExpiresIn:    int64(h.cfg.Auth.TokenExpiry.Seconds()),
		ExpiresAt:    expiresAt,
		RefreshToken: newRefreshToken,
		User: UserInfo{
			ID:     user.ID,
			Email:  user.Email,
			Role:   user.Role,
			Scopes: user.Scopes,
		},
	})
}

// Me returns the current user's information.
func (h *AuthHandler) Me(c *gin.Context) {
	claims, ok := middleware.GetClaims(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Unauthorized",
			"message": "Not authenticated",
		})
		return
	}

	c.JSON(http.StatusOK, UserInfo{
		ID:     claims.UserID,
		Email:  claims.Email,
		Role:   claims.Role,
		Scopes: claims.Scopes,
	})
}

// ValidateToken validates a JWT token and returns its claims.
func (h *AuthHandler) ValidateToken(c *gin.Context) {
	claims, ok := middleware.GetClaims(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{
			"error":   "Unauthorized",
			"message": "Invalid token",
			"valid":   false,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"valid":      true,
		"user_id":    claims.UserID,
		"email":      claims.Email,
		"role":       claims.Role,
		"scopes":     claims.Scopes,
		"expires_at": claims.ExpiresAt,
	})
}

// ----- Helper Functions -----

func (h *AuthHandler) generateToken(user *User) (string, time.Time, error) {
	expiresAt := time.Now().Add(h.cfg.Auth.TokenExpiry)

	claims := &middleware.Claims{
		UserID: user.ID,
		Email:  user.Email,
		Role:   user.Role,
		Scopes: user.Scopes,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			Issuer:    h.cfg.Auth.Issuer,
			Subject:   user.ID,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(h.cfg.Auth.JWTSecret))
	if err != nil {
		return "", time.Time{}, err
	}

	return tokenString, expiresAt, nil
}

func (h *AuthHandler) generateRefreshToken(user *User) (string, error) {
	expiresAt := time.Now().Add(h.cfg.Auth.RefreshExpiry)

	claims := &middleware.Claims{
		UserID: user.ID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    h.cfg.Auth.Issuer,
			Subject:   user.ID,
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	// Use a different secret for refresh tokens
	tokenString, err := token.SignedString([]byte(h.cfg.Auth.JWTSecret + "-refresh"))
	if err != nil {
		return "", err
	}

	return tokenString, nil
}

func generateID() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}
