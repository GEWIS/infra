package traefik_real_ip

import (
	"context"
	"net"
	"net/http"
	"strings"
)

type Config struct {
	TrustedIPs []string `json:"trustedIPs,omitempty"`
}

func CreateConfig() *Config {
	return &Config{}
}

type RealIP struct {
	next    http.Handler
	trusted []*net.IPNet
}

func New(_ context.Context, next http.Handler, config *Config, _ string) (http.Handler, error) {
	trusted := make([]*net.IPNet, 0, len(config.TrustedIPs))
	for _, entry := range config.TrustedIPs {
		network, err := parseNetwork(entry)
		if err != nil {
			return nil, err
		}
		trusted = append(trusted, network)
	}
	return &RealIP{next: next, trusted: trusted}, nil
}

func (r *RealIP) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	req.Header.Set("X-Real-Ip", r.clientIP(req))
	r.next.ServeHTTP(rw, req)
}

func (r *RealIP) clientIP(req *http.Request) string {
	peer := hostOf(req.RemoteAddr)
	if !r.isTrusted(peer) {
		return peer
	}
	hops := strings.Split(req.Header.Get("X-Forwarded-For"), ",")
	for i := len(hops) - 1; i >= 0; i-- {
		hop := strings.TrimSpace(hops[i])
		switch {
		case hop == "":
			continue
		case net.ParseIP(hop) == nil:
			return peer
		case !r.isTrusted(hop):
			return hop
		}
	}
	return peer
}

func (r *RealIP) isTrusted(address string) bool {
	ip := net.ParseIP(address)
	if ip == nil {
		return false
	}
	for _, network := range r.trusted {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func parseNetwork(entry string) (*net.IPNet, error) {
	if !strings.Contains(entry, "/") {
		if strings.Contains(entry, ":") {
			entry += "/128"
		} else {
			entry += "/32"
		}
	}
	_, network, err := net.ParseCIDR(entry)
	return network, err
}

func hostOf(address string) string {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return address
	}
	return host
}
