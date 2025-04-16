defmodule WindyfallWeb.ErrorJSONTest do
  use WindyfallWeb.ConnCase, async: true

  test "renders 404" do
    assert WindyfallWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert WindyfallWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
