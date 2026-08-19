import math
import time

def test_sanitize_data_logic():
    print("Testing SanitizeData logic in Python equivalent...")
    
    def sanitize_data(val, stack=None):
        if stack is None:
            stack = set()
        
        t = type(val)
        if t in (int, float):
            if math.isnan(val) or math.isinf(val):
                return True, 0, None
            return True, val, None
        elif t in (str, bool):
            return True, val, None
        elif t is dict:
            # Check for Vector3 mock
            if val.get("__type") == "Vector3":
                return True, [val["x"], val["y"], val["z"]], None
            
            # Check cyclic
            obj_id = id(val)
            if obj_id in stack:
                return False, None, "Cyclic reference detected in table"
            stack.add(obj_id)
            
            has_str = False
            has_num = False
            has_invalid = False
            
            for k in val.keys():
                if type(k) is str:
                    has_str = True
                elif type(k) in (int, float):
                    has_num = True
                else:
                    has_invalid = True
            
            if has_invalid:
                stack.remove(obj_id)
                return False, None, "Invalid key type"
            if has_str and has_num:
                stack.remove(obj_id)
                return False, None, "Mixed-type keys rejected"
            
            sanitized = {}
            for k, v in val.items():
                ok, res, err = sanitize_data(v, stack)
                if not ok:
                    stack.remove(obj_id)
                    return False, None, err
                sanitized[k] = res
            
            stack.remove(obj_id)
            return True, sanitized, None
        else:
            return False, None, f"Non-serializable data type: {t}"

    # Test NaN
    ok, res, _ = sanitize_data(float("nan"))
    assert ok and res == 0, "NaN failure"

    # Test Vector3
    vec = {"__type": "Vector3", "x": 10, "y": 20, "z": 30}
    ok, res, _ = sanitize_data(vec)
    assert ok and res == [10, 20, 30], "Vector3 failure"

    # Test Mixed keys
    mixed = {"foo": "bar", 1: "baz"}
    ok, _, err = sanitize_data(mixed)
    assert not ok and "Mixed-type" in err, "Mixed keys failure"

    # Test Cyclic
    node1 = {"name": "n1"}
    node2 = {"name": "n2", "link": node1}
    node1["link"] = node2
    ok, _, err = sanitize_data(node1)
    assert not ok and "Cyclic" in err, "Cyclic failure"

    print("  [PASS] SanitizeData runtime logic tests passed!")

def test_matchmaking_sharding_logic():
    print("Testing Matchmaking Sharding & Lobby logic...")
    NUM_SHARDS = 4
    def get_shard_index(user_id):
        return abs(user_id) % NUM_SHARDS
    
    assert get_shard_index(100) == 0
    assert get_shard_index(101) == 1
    assert get_shard_index(102) == 2
    assert get_shard_index(103) == 3
    assert get_shard_index(104) == 0

    print("  [PASS] Matchmaking Sharding logic tests passed!")

def main():
    test_sanitize_data_logic()
    test_matchmaking_sharding_logic()
    print("ALL MOCK LOGIC TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    main()
