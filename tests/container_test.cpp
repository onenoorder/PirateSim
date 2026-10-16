#include <gtest/gtest.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

// Smoke test proving Google Test is wired and discoverable by CTest inside the
// container (story SDG-008 AC5). Real unit tests will be added alongside their
// modules per the project test strategy.

namespace {

TEST(ContainerTest, GTestIsWired) {
    ASSERT_TRUE(true);
}

TEST(ContainerTest, GlmIsUsable) {
    glm::vec3 translate(1.0f, 2.0f, 3.0f);
    glm::mat4 model = glm::translate(glm::mat4(1.0f), translate);
    EXPECT_FLOAT_EQ(model[3].x, 1.0f);
    EXPECT_FLOAT_EQ(model[3].y, 2.0f);
    EXPECT_FLOAT_EQ(model[3].z, 3.0f);
}

} // namespace
