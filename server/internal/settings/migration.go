package settings

import "fmt"

func validateVersion(version int) error {
	if version != 1 { return fmt.Errorf("不支持的配置版本: %d, 当前版本为 1", version) }
	return nil
}
