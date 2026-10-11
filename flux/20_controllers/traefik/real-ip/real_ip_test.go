package traefik_real_ip

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestClientIP(t *testing.T) {
	const waf = "131.155.10.134"
	const geproxy = "145.116.44.49"
	cases := []struct {
		name       string
		remoteAddr string
		xff        string
		xRealIP    string
		want       string
	}{
		{"untrusted peer ignores forged headers", "198.51.100.7:4711", "1.2.3.4", "5.6.7.8", "198.51.100.7"},
		{"waf appends client to forged chain", waf + ":443", "1.2.3.4, 198.51.100.7", "5.6.7.8", "198.51.100.7"},
		{"waf entry already appended", waf + ":443", "1.2.3.4, 198.51.100.7, " + waf, "", "198.51.100.7"},
		{"chain of trusted proxies", waf + ":443", "198.51.100.7, " + geproxy, "", "198.51.100.7"},
		{"trusted peer without header", waf + ":443", "", "", waf},
		{"only trusted hops", waf + ":443", geproxy, "", waf},
		{"garbage right of client", waf + ":443", "198.51.100.7, not-an-ip", "", waf},
		{"ipv6 peer", "[2001:db8::1]:4711", "", "", "2001:db8::1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var got string
			next := http.HandlerFunc(func(_ http.ResponseWriter, req *http.Request) {
				got = req.Header.Get("X-Real-Ip")
			})
			config := CreateConfig()
			config.TrustedIPs = []string{"131.155.10.134", "131.155.10.135", "145.116.44.49/32"}
			handler, err := New(context.Background(), next, config, "real-ip")
			if err != nil {
				t.Fatal(err)
			}
			req := httptest.NewRequest(http.MethodGet, "https://example.gewis.nl/", nil)
			req.RemoteAddr = tc.remoteAddr
			if tc.xff != "" {
				req.Header.Set("X-Forwarded-For", tc.xff)
			}
			if tc.xRealIP != "" {
				req.Header.Set("X-Real-Ip", tc.xRealIP)
			}
			handler.ServeHTTP(httptest.NewRecorder(), req)
			if got != tc.want {
				t.Fatalf("X-Real-Ip = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestInvalidTrustedIP(t *testing.T) {
	config := CreateConfig()
	config.TrustedIPs = []string{"not-an-ip"}
	if _, err := New(context.Background(), http.NotFoundHandler(), config, "real-ip"); err == nil {
		t.Fatal("expected an error for an invalid trusted IP")
	}
}
