package settings

import (
	"encoding/json"
	"errors"
	"io"
	"os"
)

type Settings struct {
	SchemaVersion int `json:"schemaVersion"`
	Listen string `json:"listen"`
	DataDirectory string `json:"dataDirectory"`
	TLSCertificate string `json:"tlsCertificate"`
	TLSKey string `json:"tlsKey"`
	AccessTokenSeconds int `json:"accessTokenSeconds"`
	RefreshTokenSeconds int `json:"refreshTokenSeconds"`
}

func Load(filename string) (Settings, error) {
	s := Settings{SchemaVersion:1, Listen:"127.0.0.1:8080", DataDirectory:"data", AccessTokenSeconds:900, RefreshTokenSeconds:2592000}
	if filename != "" {
		file, err := os.Open(filename)
		if err != nil { return s, err }
		defer file.Close()
		d := json.NewDecoder(file)
		d.DisallowUnknownFields()
		// 文件必须显式声明版本, 默认值只用于无文件启动.
		s.SchemaVersion = 0
		if err := d.Decode(&s); err != nil { return s, err }
		if d.Decode(new(any)) != io.EOF { return s, errors.New("配置包含多余数据") }
	}
	if err := validateVersion(s.SchemaVersion); err != nil { return s, err }
	if s.AccessTokenSeconds < 60 || s.RefreshTokenSeconds <= s.AccessTokenSeconds || s.DataDirectory == "" || (s.TLSCertificate == "") != (s.TLSKey == "") { return s, errors.New("服务端配置无效") }
	return s, nil
}
