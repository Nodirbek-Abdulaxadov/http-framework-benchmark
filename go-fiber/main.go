package main

import (
	"crypto/sha256"
	"fmt"
	"time"

	"github.com/gofiber/fiber/v2"
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

func main() {
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

	app.Listen(":8080")
}