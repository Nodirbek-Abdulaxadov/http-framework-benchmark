package main

import (
	"context"
	"crypto/sha256"
	"fmt"
	"math/rand"
	"os"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/jackc/pgx/v5/pgxpool"
)

type SmallResponse struct {
	Id     int    `json:"id"`
	Name   string `json:"name"`
	Active bool   `json:"active"`
}

type LargeResponse struct {
	Id    int    `json:"id"`
	Name  string `json:"name"`
	Value int    `json:"value"`
}

type World struct {
	Id           int `json:"id"`
	RandomNumber int `json:"randomNumber"`
}

var pool *pgxpool.Pool

// clampQueries mirrors the TechEmpower rule every stack here follows: a missing
// or unparsable ?queries= is 1, and the value is pinned to 1..500.
func clampQueries(raw string) int {
	n, err := strconv.Atoi(raw)
	if err != nil {
		return 1
	}
	if n < 1 {
		return 1
	}
	if n > 500 {
		return 500
	}
	return n
}

func fetchWorld(ctx context.Context, id int) (World, error) {
	var w World
	err := pool.QueryRow(ctx, "SELECT id, randomnumber FROM world WHERE id = $1", id).
		Scan(&w.Id, &w.RandomNumber)
	return w, err
}

func main() {
	// DB tier (/db, /queries, /updates). Pool capped at 64 to match jwc's
	// JWC_DB_POOL_SIZE default and the bench's 64 concurrent connections.
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://postgres:1234@localhost:5432/BenchJWCDB"
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		panic(err)
	}
	cfg.MaxConns = 64
	pool, err = pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		panic(err)
	}
	defer pool.Close()

	app := fiber.New(fiber.Config{
		Prefork: false,
	})

	app.Get("/ping", func(c *fiber.Ctx) error {
		return c.SendString("pong")
	})

	app.Get("/json-small", func(c *fiber.Ctx) error {
		return c.JSON(SmallResponse{
			Id:     1,
			Name:   "Test",
			Active: true,
		})
	})

	app.Get("/json-large", func(c *fiber.Ctx) error {
		items := make([]LargeResponse, 1000)

		for i := 0; i < 1000; i++ {
			items[i] = LargeResponse{
				Id:    i,
				Name:  fmt.Sprintf("Item %d", i),
				Value: i * 10,
			}
		}

		return c.JSON(items)
	})

	app.Get("/cpu", func(c *fiber.Ctx) error {
		data := []byte("benchmark")

		for i := 0; i < 100000; i++ {
			hash := sha256.Sum256(data)
			data = hash[:]
		}

		return c.SendString("done")
	})

	app.Get("/async-delay", func(c *fiber.Ctx) error {
		time.Sleep(10 * time.Millisecond)
		return c.SendString("ok")
	})

	// -------------------- DB tier --------------------

	app.Get("/db", func(c *fiber.Ctx) error {
		w, err := fetchWorld(c.Context(), rand.Intn(10000)+1)
		if err != nil {
			return err
		}
		return c.JSON(w)
	})

	app.Get("/queries", func(c *fiber.Ctx) error {
		n := clampQueries(c.Query("queries"))
		rows := make([]World, n)
		for i := 0; i < n; i++ {
			w, err := fetchWorld(c.Context(), rand.Intn(10000)+1)
			if err != nil {
				return err
			}
			rows[i] = w
		}
		return c.JSON(rows)
	})

	app.Get("/updates", func(c *fiber.Ctx) error {
		n := clampQueries(c.Query("queries"))
		rows := make([]World, n)
		for i := 0; i < n; i++ {
			w, err := fetchWorld(c.Context(), rand.Intn(10000)+1)
			if err != nil {
				return err
			}
			w.RandomNumber = rand.Intn(10000) + 1
			if _, err := pool.Exec(c.Context(),
				"UPDATE world SET randomnumber = $1 WHERE id = $2", w.RandomNumber, w.Id); err != nil {
				return err
			}
			rows[i] = w
		}
		return c.JSON(rows)
	})

	app.Listen(":8080")
}